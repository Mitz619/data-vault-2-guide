/* ============================================================================
   POINT-IN-TIME (PIT) BUILD PATTERN — Data Vault 2.0
   Snapshot the correct Satellite LOAD_DTS per Hub/Link key at specific
   moments in time. Enables fast equi-joins at query time (no correlated MAX).

   PIT tables are SYSTEM-DRIVEN (SYSGEN) — drop and rebuild at any time
   without affecting the Raw Vault.
   Written for SQL Server (T-SQL).
============================================================================ */

/* ── PIT_CUSTOMER — daily snapshots ────────────────────────────────────── */

/* Step 1: Generate the snapshot dates to populate (typically daily) */
;WITH snapshot_dates AS (
    /* All dates from the earliest Hub LOAD_DTS up to today */
    SELECT CAST(MIN(LOAD_DTS) AS DATE) AS snapshot_date
    FROM [raw_vault].[HUB_CUSTOMER]
    UNION ALL
    SELECT DATEADD(DAY, 1, snapshot_date)
    FROM snapshot_dates
    WHERE snapshot_date < CAST(GETDATE() AS DATE)
)
/* Step 2: Cross-join dates × customers, then pick the latest LOAD_DTS per
           satellite that is <= the snapshot date */
INSERT INTO [info_mart].[PIT_CUSTOMER]
    (SNAPSHOT_DTS, CUSTOMER_HK, SAT_PROFILE_LOAD_DTS, SAT_ADDRESS_LOAD_DTS, REC_SRC)
SELECT
    CAST(d.snapshot_date AS DATETIME2)  AS SNAPSHOT_DTS,
    h.CUSTOMER_HK,

    /* Latest SAT_CUSTOMER_PROFILE version as-of this snapshot */
    (
        SELECT MAX(p.LOAD_DTS)
        FROM [raw_vault].[SAT_CUSTOMER_PROFILE] p
        WHERE p.CUSTOMER_HK = h.CUSTOMER_HK
          AND p.LOAD_DTS   <= CAST(d.snapshot_date AS DATETIME2)
    )                                   AS SAT_PROFILE_LOAD_DTS,

    /* Latest SAT_CUSTOMER_ADDRESS version as-of this snapshot */
    (
        SELECT MAX(a.LOAD_DTS)
        FROM [raw_vault].[SAT_CUSTOMER_ADDRESS] a
        WHERE a.CUSTOMER_HK = h.CUSTOMER_HK
          AND a.LOAD_DTS   <= CAST(d.snapshot_date AS DATETIME2)
    )                                   AS SAT_ADDRESS_LOAD_DTS,

    'SYSGEN'                            AS REC_SRC  -- system-generated, not a source
FROM [raw_vault].[HUB_CUSTOMER] h
CROSS JOIN snapshot_dates d
OPTION (MAXRECURSION 3650)  -- 10 years of daily dates
;

/* ── QUERYING WITH PIT — equi-join pattern (replaces correlated MAX) ───── */

/*
   WITHOUT PIT — slow: correlated subquery per satellite
   -------------------------------------------------------
   SELECT p.EMAIL_ADDRESS, a.SUBURB
   FROM raw_vault.HUB_CUSTOMER h
   JOIN raw_vault.SAT_CUSTOMER_PROFILE p
     ON p.CUSTOMER_HK = h.CUSTOMER_HK
    AND p.LOAD_DTS = (
        SELECT MAX(LOAD_DTS) FROM raw_vault.SAT_CUSTOMER_PROFILE
        WHERE CUSTOMER_HK = h.CUSTOMER_HK AND LOAD_DTS <= '2026-06-11 23:59'
    )
   JOIN raw_vault.SAT_CUSTOMER_ADDRESS a
     ON a.CUSTOMER_HK = h.CUSTOMER_HK
    AND a.LOAD_DTS = (
        SELECT MAX(LOAD_DTS) FROM raw_vault.SAT_CUSTOMER_ADDRESS
        WHERE CUSTOMER_HK = h.CUSTOMER_HK AND LOAD_DTS <= '2026-06-11 23:59'
    );

   WITH PIT — fast: pure equi-joins (optimiser-friendly)
   -------------------------------------------------------
*/
SELECT
    p.EMAIL_ADDRESS,
    a.SUBURB
FROM [info_mart].[PIT_CUSTOMER] pit
JOIN [raw_vault].[SAT_CUSTOMER_PROFILE] p
    ON  p.CUSTOMER_HK = pit.CUSTOMER_HK
    AND p.LOAD_DTS    = pit.SAT_PROFILE_LOAD_DTS
JOIN [raw_vault].[SAT_CUSTOMER_ADDRESS] a
    ON  a.CUSTOMER_HK = pit.CUSTOMER_HK
    AND a.LOAD_DTS    = pit.SAT_ADDRESS_LOAD_DTS
WHERE pit.SNAPSHOT_DTS = '2026-06-11 23:59:00';

/* ============================================================================
   PIT DESIGN NOTES
   ----------------
   1. PIT is SYSGEN — REC_SRC = 'SYSGEN'. Drop and rebuild whenever needed.
   2. One PIT per Hub (or one per Link for link-level queries).
   3. Columns: SNAPSHOT_DTS (PK) + parent _HK (PK) + one LOAD_DTS column
      per Satellite attached to that Hub/Link.
   4. If a Satellite has no row as-of a snapshot date, the LOAD_DTS column
      is NULL — the join will return no satellite row for that snapshot.
      Handle NULLs in the consuming query or dimension view.
   5. Incremental rebuild: only insert new SNAPSHOT_DTS values; don't rebuild
      the full history on every run. Use a watermark on SNAPSHOT_DTS.
   6. At scale, materialise the PIT as a table and refresh it incrementally
      via dbt incremental models or a stored procedure + watermark.
============================================================================ */
