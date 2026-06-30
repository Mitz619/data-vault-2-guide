/* ============================================================================
   DATA PROFILING TOOLKIT
   A reusable battery of checks to run against any new source table before you
   trust it. Written for SQL Server (T-SQL). See the dialect table below to port
   to BigQuery.

   HOW TO USE
   ----------
   1. Replace the placeholders:
        {{SCHEMA}}   schema name      e.g. genesys
        {{TABLE}}    table name       e.g. conversation
        {{COLUMN}}   a single column  e.g. status
        {{DATECOL}}  a date column    e.g. conversation_start
        {{NUMCOL}}   a numeric column e.g. handle_time_seconds
        {{KEY}}      the business key e.g. post_office_id
   2. Run section by section. Start with 1-3 (overview, grain, completeness) on
      every table; the rest are pull-as-needed.
   3. Record a verdict next to each finding: ASSUMED / CONFIRMED / VIOLATED.
      Keep this file per source so the next person inherits the proof.

   PERFORMANCE NOTE
   ----------------
   COUNT(DISTINCT ...) and full-column scans are expensive on large tables.
   For tables over a few million rows, profile on a sample first:
        FROM [{{SCHEMA}}].[{{TABLE}}] TABLESAMPLE (1 PERCENT)
   then re-run the few checks that matter on the full table.

   DIALECT QUICK-MAP (T-SQL  ->  BigQuery)
   ---------------------------------------
     [schema].[table]          ->  `project.dataset.table`   (backticks)
     GETDATE()                 ->  CURRENT_TIMESTAMP()
     LEN(x)                    ->  LENGTH(x)
     ISNULL(x,y)               ->  IFNULL(x,y)
     STDEV(x)                  ->  STDDEV(x)
     TOP n ...                 ->  ... LIMIT n
     EXCEPT                    ->  EXCEPT DISTINCT
     FORMAT(d,'yyyy-MM')       ->  FORMAT_DATE('%Y-%m', d)
     EOMONTH / DATEFROMPARTS   ->  DATE_TRUNC(d, MONTH)
     sys.columns catalog       ->  INFORMATION_SCHEMA.COLUMNS
     sp_executesql             ->  EXECUTE IMMEDIATE
============================================================================ */


/* ============================================================================
   SECTION 1 — TABLE OVERVIEW   (run on every table)
   "How big is this, and how fresh?"
============================================================================ */

-- 1.1 Exact row count
SELECT COUNT(*) AS total_rows
FROM [{{SCHEMA}}].[{{TABLE}}];

-- 1.2 Fast approximate row count for very large tables (no scan)
SELECT SUM(p.rows) AS approx_rows
FROM sys.partitions p
JOIN sys.objects o   ON o.object_id = p.object_id
JOIN sys.schemas s   ON s.schema_id = o.schema_id
WHERE s.name = '{{SCHEMA}}' AND o.name = '{{TABLE}}' AND p.index_id IN (0,1);

-- 1.3 Data freshness — how recent is the newest record?
SELECT MIN([{{DATECOL}}]) AS earliest,
       MAX([{{DATECOL}}]) AS latest,
       DATEDIFF(DAY, MAX([{{DATECOL}}]), GETDATE()) AS days_since_last_record
FROM [{{SCHEMA}}].[{{TABLE}}];


/* ============================================================================
   SECTION 2 — GRAIN & UNIQUENESS   (run on every table)
   "What does one row represent, and is that actually true?"
============================================================================ */

-- 2.1 Is {{KEY}} unique? (rows vs distinct keys — if they differ, you have dupes)
SELECT COUNT(*)                  AS total_rows,
       COUNT(DISTINCT [{{KEY}}]) AS distinct_keys,
       COUNT(*) - COUNT(DISTINCT [{{KEY}}]) AS duplicate_rows
FROM [{{SCHEMA}}].[{{TABLE}}];

-- 2.2 Show the actual duplicate keys (and how many times each repeats)
SELECT [{{KEY}}], COUNT(*) AS occurrences
FROM [{{SCHEMA}}].[{{TABLE}}]
GROUP BY [{{KEY}}]
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;

-- 2.3 Composite-key uniqueness test (replace with your candidate grain columns)
SELECT [col_a], [col_b], COUNT(*) AS occurrences
FROM [{{SCHEMA}}].[{{TABLE}}]
GROUP BY [col_a], [col_b]
HAVING COUNT(*) > 1;

-- 2.4 Fan-out profile — how many rows per key? (reveals 1:1 vs 1:many grain)
SELECT occurrences, COUNT(*) AS keys_with_this_many
FROM (
    SELECT [{{KEY}}], COUNT(*) AS occurrences
    FROM [{{SCHEMA}}].[{{TABLE}}]
    GROUP BY [{{KEY}}]
) t
GROUP BY occurrences
ORDER BY occurrences;


/* ============================================================================
   SECTION 3 — COMPLETENESS / NULL PROFILING   (run on every table)
   "Which columns are reliably populated, and which are mostly empty?"
============================================================================ */

-- 3.1 Single-column NULL profile
SELECT COUNT(*)                                       AS total_rows,
       COUNT([{{COLUMN}}])                            AS populated,
       COUNT(*) - COUNT([{{COLUMN}}])                 AS nulls,
       CAST(100.0 * (COUNT(*) - COUNT([{{COLUMN}}]))
            / NULLIF(COUNT(*),0) AS DECIMAL(5,2))      AS null_pct
FROM [{{SCHEMA}}].[{{TABLE}}];

-- 3.2 *** AUTO-PROFILER: NULL % + distinct count for EVERY column ***
--     Generates and runs one query. This is the workhorse — start here.
DECLARE @schema sysname = '{{SCHEMA}}';
DECLARE @table  sysname = '{{TABLE}}';
DECLARE @sql    nvarchar(max);

SELECT @sql = STRING_AGG(
    'SELECT ''' + c.name + ''' AS column_name'
  + ', COUNT(*) AS total_rows'
  + ', COUNT([' + c.name + ']) AS populated'
  + ', COUNT(*) - COUNT([' + c.name + ']) AS nulls'
  + ', CAST(100.0*(COUNT(*)-COUNT([' + c.name + ']))/NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS null_pct'
  + ', COUNT(DISTINCT [' + c.name + ']) AS distinct_vals'
  + ' FROM [' + @schema + '].[' + @table + ']'
  , ' UNION ALL ')
  WITHIN GROUP (ORDER BY c.column_id)
FROM sys.columns c
JOIN sys.objects o ON o.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = @schema AND o.name = @table
  -- skip large blob types that can't be DISTINCT-counted:
  AND c.system_type_id NOT IN (34,35,99,241); -- image, text, ntext, xml

EXEC sp_executesql @sql;


/* ============================================================================
   SECTION 4 — CARDINALITY / DISTINCTNESS
   "Is this column a flag, a category, an ID, or free text?"
============================================================================ */

-- 4.1 Distinct count and ratio for one column
SELECT COUNT(DISTINCT [{{COLUMN}}]) AS distinct_vals,
       COUNT(*)                     AS total_rows,
       CAST(100.0 * COUNT(DISTINCT [{{COLUMN}}])
            / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS distinct_pct
FROM [{{SCHEMA}}].[{{TABLE}}];
-- Reading it: distinct_pct ~100% => looks like a key.
--             very low (e.g. <20 distinct) => candidate flag / dimension attribute.


/* ============================================================================
   SECTION 5 — VALUE DISTRIBUTION / FREQUENCY
   "What values actually live in this column, and how common is each?"
============================================================================ */

-- 5.1 Top values by frequency (NULLs shown explicitly)
SELECT TOP 30
       ISNULL(CAST([{{COLUMN}}] AS varchar(100)), '(NULL)') AS value,
       COUNT(*) AS occurrences,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct
FROM [{{SCHEMA}}].[{{TABLE}}]
GROUP BY [{{COLUMN}}]
ORDER BY occurrences DESC;

-- 5.2 Populated vs blank vs NULL breakdown (catches empty-string-vs-NULL traps)
SELECT
    SUM(CASE WHEN [{{COLUMN}}] IS NULL                       THEN 1 ELSE 0 END) AS is_null,
    SUM(CASE WHEN [{{COLUMN}}] = ''                          THEN 1 ELSE 0 END) AS is_blank,
    SUM(CASE WHEN [{{COLUMN}}] IS NOT NULL
              AND LTRIM(RTRIM([{{COLUMN}}])) <> ''           THEN 1 ELSE 0 END) AS is_populated
FROM [{{SCHEMA}}].[{{TABLE}}];


/* ============================================================================
   SECTION 6 — NUMERIC PROFILING
   "Range, spread, and suspicious values for a number column."
============================================================================ */

-- 6.1 Summary stats
SELECT MIN([{{NUMCOL}}])               AS min_val,
       MAX([{{NUMCOL}}])               AS max_val,
       AVG(CAST([{{NUMCOL}}] AS float)) AS avg_val,
       STDEV(CAST([{{NUMCOL}}] AS float)) AS std_dev,
       SUM(CASE WHEN [{{NUMCOL}}] < 0 THEN 1 ELSE 0 END) AS negatives,
       SUM(CASE WHEN [{{NUMCOL}}] = 0 THEN 1 ELSE 0 END) AS zeros,
       SUM(CASE WHEN [{{NUMCOL}}] IS NULL THEN 1 ELSE 0 END) AS nulls
FROM [{{SCHEMA}}].[{{TABLE}}];

-- 6.2 Outliers beyond 3 standard deviations (data-entry errors, units mismatch)
WITH stats AS (
    SELECT AVG(CAST([{{NUMCOL}}] AS float)) AS m,
           STDEV(CAST([{{NUMCOL}}] AS float)) AS sd
    FROM [{{SCHEMA}}].[{{TABLE}}]
)
SELECT COUNT(*) AS outlier_rows
FROM [{{SCHEMA}}].[{{TABLE}}] t CROSS JOIN stats s
WHERE t.[{{NUMCOL}}] > s.m + 3*s.sd
   OR t.[{{NUMCOL}}] < s.m - 3*s.sd;


/* ============================================================================
   SECTION 7 — DATE / TEMPORAL PROFILING
   "Range, gaps, future dates, and sentinel values for a date column."
============================================================================ */

-- 7.1 Range + suspicious dates
SELECT MIN([{{DATECOL}}]) AS earliest,
       MAX([{{DATECOL}}]) AS latest,
       SUM(CASE WHEN [{{DATECOL}}] IS NULL          THEN 1 ELSE 0 END) AS null_dates,
       SUM(CASE WHEN [{{DATECOL}}] > GETDATE()      THEN 1 ELSE 0 END) AS future_dates,
       SUM(CASE WHEN [{{DATECOL}}] IN ('1900-01-01','9999-12-31')
                                                    THEN 1 ELSE 0 END) AS sentinel_dates
FROM [{{SCHEMA}}].[{{TABLE}}];

-- 7.2 Volume over time (spot load gaps, spikes, and where history really starts)
SELECT YEAR([{{DATECOL}}]) AS yr,
       MONTH([{{DATECOL}}]) AS mth,
       COUNT(*) AS rows
FROM [{{SCHEMA}}].[{{TABLE}}]
WHERE [{{DATECOL}}] IS NOT NULL
GROUP BY YEAR([{{DATECOL}}]), MONTH([{{DATECOL}}])
ORDER BY yr, mth;


/* ============================================================================
   SECTION 8 — STRING / TEXT PROFILING
   "Hidden whitespace, casing inconsistencies, and length surprises."
============================================================================ */

-- 8.1 Length profile
SELECT MIN(LEN([{{COLUMN}}])) AS min_len,
       MAX(LEN([{{COLUMN}}])) AS max_len,
       AVG(LEN([{{COLUMN}}])) AS avg_len
FROM [{{SCHEMA}}].[{{TABLE}}]
WHERE [{{COLUMN}}] IS NOT NULL;

-- 8.2 Leading/trailing whitespace (invisible, breaks joins and grouping)
SELECT COUNT(*) AS rows_with_stray_whitespace
FROM [{{SCHEMA}}].[{{TABLE}}]
WHERE [{{COLUMN}}] <> LTRIM(RTRIM([{{COLUMN}}]));

-- 8.3 Casing inconsistency — same value stored differently (e.g. 'NSW' vs 'nsw')
--     If distinct_raw > distinct_normalised, your data has casing drift.
SELECT COUNT(DISTINCT [{{COLUMN}}])              AS distinct_raw,
       COUNT(DISTINCT UPPER(LTRIM(RTRIM([{{COLUMN}}])))) AS distinct_normalised
FROM [{{SCHEMA}}].[{{TABLE}}];


/* ============================================================================
   SECTION 9 — REFERENTIAL INTEGRITY / ORPHANS
   "Do child keys actually exist in the parent?"
============================================================================ */

-- 9.1 Orphans — child rows whose key is missing from the parent
SELECT COUNT(*) AS orphan_rows
FROM [{{SCHEMA}}].[child_table]  c
LEFT JOIN [{{SCHEMA}}].[parent_table] p
       ON p.[{{KEY}}] = c.[{{KEY}}]
WHERE p.[{{KEY}}] IS NULL
  AND c.[{{KEY}}] IS NOT NULL;


/* ============================================================================
   SECTION 10 — BUSINESS-RULE CONTRADICTION CHECKS
   "Where does the data violate what the business swears is true?"
   Adapt these to your defined rules (BR001, BR002, ...).
============================================================================ */

-- 10.1 Status vs date contradiction (the classic: "OPEN" but has a closure date)
SELECT COUNT(*) AS contradictions
FROM [{{SCHEMA}}].[{{TABLE}}]
WHERE [status] = 'OPEN'
  AND [closure_date] IS NOT NULL;

-- 10.2 Date order violation (an end before its start)
SELECT COUNT(*) AS bad_date_order
FROM [{{SCHEMA}}].[{{TABLE}}]
WHERE [closure_date] < [operational_start_date];

-- 10.3 Mutually exclusive flags both set (adapt column names)
SELECT COUNT(*) AS impossible_combo
FROM [{{SCHEMA}}].[{{TABLE}}]
WHERE [is_active] = 1 AND [is_deleted] = 1;


/* ============================================================================
   SECTION 11 — CROSS-SOURCE RECONCILIATION
   "Do two systems that should agree actually agree?"
============================================================================ */

-- 11.1 Row-count comparison between two systems
SELECT 'system_a' AS source, COUNT(*) AS rows FROM [{{SCHEMA}}].[system_a_table]
UNION ALL
SELECT 'system_b',           COUNT(*)         FROM [{{SCHEMA}}].[system_b_table];

-- 11.2 Keys in A but not in B (then flip the SELECTs for the reverse)
SELECT [{{KEY}}] FROM [{{SCHEMA}}].[system_a_table]
EXCEPT
SELECT [{{KEY}}] FROM [{{SCHEMA}}].[system_b_table];


/* ============================================================================
   SECTION 12 — DISTINCT-VALUE DICTIONARY (low-cardinality columns)
   "List every value of a categorical column — your future dimension members."
============================================================================ */

-- 12.1 Run for any column you suspect is a code/flag/category
SELECT [{{COLUMN}}] AS value, COUNT(*) AS rows
FROM [{{SCHEMA}}].[{{TABLE}}]
GROUP BY [{{COLUMN}}]
ORDER BY [{{COLUMN}}];

/* ============================================================================
   END OF TOOLKIT
   Workflow reminder: Section 1-3 on every new table, then pull 4-12 as the
   data raises questions. Record verdicts. Keep the file. Hand it over.
============================================================================ */
