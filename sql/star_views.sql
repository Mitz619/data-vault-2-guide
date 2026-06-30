/* ============================================================================
   INFORMATION MART — STAR SCHEMA VIEWS
   Dimension and fact views over the Raw Vault for Power BI / Tableau.
   Written for SQL Server (T-SQL).

   Naming: VDIM_ for dimension views, VF_ for fact views.
   These are TYPE 1 (current value) views. The vault preserves all history —
   rebuild as Type 2 SCD at any time without re-sourcing from operational systems.
============================================================================ */

/* ── VDIM_CUSTOMER — current customer attributes (Type 1) ──────────────── */
CREATE OR ALTER VIEW [info_mart].[VDIM_CUSTOMER] AS
SELECT
    h.CUSTOMER_HK           AS CUSTOMER_KEY,    -- surrogate for BI joins
    h.CUSTOMER_NUMBER,                           -- natural/degenerate key
    p.FULL_NAME,
    p.EMAIL_ADDRESS,
    p.PHONE_NUMBER,
    p.LOYALTY_TIER,
    a.STREET_ADDRESS,
    a.SUBURB,
    a.STATE_CODE,
    a.POSTCODE
FROM [raw_vault].[HUB_CUSTOMER] h
/* Latest profile row */
OUTER APPLY (
    SELECT TOP 1 FULL_NAME, EMAIL_ADDRESS, PHONE_NUMBER, LOYALTY_TIER
    FROM [raw_vault].[SAT_CUSTOMER_PROFILE]
    WHERE CUSTOMER_HK = h.CUSTOMER_HK
    ORDER BY LOAD_DTS DESC
) p
/* Latest address row */
OUTER APPLY (
    SELECT TOP 1 STREET_ADDRESS, SUBURB, STATE_CODE, POSTCODE
    FROM [raw_vault].[SAT_CUSTOMER_ADDRESS]
    WHERE CUSTOMER_HK = h.CUSTOMER_HK
    ORDER BY LOAD_DTS DESC
) a;
GO

/* ── VDIM_PRODUCT — current product attributes (Type 1) ────────────────── */
CREATE OR ALTER VIEW [info_mart].[VDIM_PRODUCT] AS
SELECT
    h.PRODUCT_HK            AS PRODUCT_KEY,
    h.PRODUCT_CODE,
    d.PRODUCT_NAME,
    d.CATEGORY,
    d.BRAND,
    d.UNIT_PRICE
FROM [raw_vault].[HUB_PRODUCT] h
OUTER APPLY (
    SELECT TOP 1 PRODUCT_NAME, CATEGORY, BRAND, UNIT_PRICE
    FROM [raw_vault].[SAT_PRODUCT_DETAILS]
    WHERE PRODUCT_HK = h.PRODUCT_HK
    ORDER BY LOAD_DTS DESC
) d;
GO

/* ── VDIM_DATE — calendar dimension (stand-alone table, no vault parent) ── */
/* Typically pre-built as a physical table; shown here as a simple view */
CREATE OR ALTER VIEW [info_mart].[VDIM_DATE] AS
SELECT
    CAST(FORMAT(d, 'yyyyMMdd') AS INT)  AS DATE_KEY,
    CAST(d AS DATE)                     AS CALENDAR_DATE,
    DATENAME(WEEKDAY, d)                AS DAY_NAME,
    DATENAME(MONTH, d)                  AS MONTH_NAME,
    YEAR(d)                             AS YEAR,
    MONTH(d)                            AS MONTH_NUMBER,
    DAY(d)                              AS DAY_OF_MONTH,
    DATEPART(QUARTER, d)                AS QUARTER
FROM (
    -- Generate 10 years of dates via a numbers tally
    SELECT DATEADD(DAY, n.number, '2020-01-01') AS d
    FROM master..spt_values n
    WHERE n.type = 'P' AND n.number BETWEEN 0 AND 3649
) dates;
GO

/* ── VF_SALES — order-line fact (grain: one row per order line) ─────────── */
CREATE OR ALTER VIEW [info_mart].[VF_SALES] AS
SELECT
    /* Date dimension FK */
    CAST(FORMAT(CAST(l.LOAD_DTS AS DATE), 'yyyyMMdd') AS INT)  AS DATE_KEY,

    /* Dimension FKs */
    l.CUSTOMER_HK           AS CUSTOMER_KEY,
    l.PRODUCT_HK            AS PRODUCT_KEY,
    oc.CHANNEL_HK           AS CHANNEL_KEY,
    op.PAYMENT_METHOD_HK    AS PAYMENT_METHOD_KEY,

    /* Degenerate dimension — business key carried on the fact */
    ho.ORDER_NUMBER,

    /* Measures from the Link Satellite */
    d.QUANTITY,
    d.UNIT_PRICE_SOLD,
    d.DISCOUNT_PCT,
    d.LINE_TOTAL

FROM [raw_vault].[LNK_ORDER_ITEM] l

/* Order number from Hub (degenerate dimension) */
JOIN [raw_vault].[HUB_ORDER] ho
    ON ho.ORDER_HK = l.ORDER_HK

/* Optional: channel via LNK_ORDER_CHANNEL */
LEFT JOIN [raw_vault].[LNK_ORDER_CHANNEL] oc
    ON oc.ORDER_HK = l.ORDER_HK

/* Optional: payment method via LNK_ORDER_PAYMENT */
LEFT JOIN [raw_vault].[LNK_ORDER_PAYMENT] op
    ON op.ORDER_HK = l.ORDER_HK

/* Latest order item details */
OUTER APPLY (
    SELECT TOP 1 QUANTITY, UNIT_PRICE_SOLD, DISCOUNT_PCT, LINE_TOTAL
    FROM [raw_vault].[SAT_ORDER_ITEM_DETAILS]
    WHERE ORDER_ITEM_HK = l.ORDER_ITEM_HK
    ORDER BY LOAD_DTS DESC
) d

/* Exclude lines where no item detail exists yet */
WHERE d.QUANTITY IS NOT NULL;
GO

/* ============================================================================
   INFORMATION MART NOTES
   ----------------------
   1. OUTER APPLY TOP 1 ORDER BY LOAD_DTS DESC = Type 1 (current value).
      To get Type 2, join through PIT_CUSTOMER on a specific SNAPSHOT_DTS.
   2. These are VIEWS — disposable. Drop and recreate freely; the Raw Vault
      is the source of truth.
   3. For Power BI import mode at scale: materialise as physical tables
      refreshed by a stored proc or dbt incremental model.
   4. For Power BI DirectQuery: index LOAD_DTS on all Satellite tables
      and use OUTER APPLY or LEFT JOIN LATERAL (PostgreSQL/BigQuery).
   5. Hard business rules (typing, hashing, PII scrubbing) belong in staging.
      Only SOFT rules (scoring, derived attributes) go in the Business Vault
      or Information Mart — never in the Raw Vault.
============================================================================ */
