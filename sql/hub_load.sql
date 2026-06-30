/* ============================================================================
   HUB LOAD PATTERN — Data Vault 2.0
   Insert business keys never seen before. Idempotent: re-running is a no-op.
   Written for SQL Server (T-SQL). See dialect notes for BigQuery / Snowflake.

   DIALECT NOTES
   -------------
   SQL Server : HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(business_key))))
   PostgreSQL : md5(upper(trim(business_key)))::uuid
   BigQuery   : TO_HEX(SHA256(UPPER(TRIM(business_key))))
   Snowflake  : SHA2(UPPER(TRIM(business_key)))
============================================================================ */

/* ── HUB_CUSTOMER ──────────────────────────────────────────────────────── */
INSERT INTO [raw_vault].[HUB_CUSTOMER]
    (CUSTOMER_HK, CUSTOMER_NUMBER, LOAD_DTS, REC_SRC)
SELECT DISTINCT
    HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.CUSTOMER_NUMBER)))), -- deterministic hash
    s.CUSTOMER_NUMBER,
    s.LOAD_DTS,
    s.REC_SRC
FROM [staging].[STG_ORDERS] s
WHERE NOT EXISTS (
    SELECT 1
    FROM [raw_vault].[HUB_CUSTOMER] h
    WHERE h.CUSTOMER_HK = HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.CUSTOMER_NUMBER))))
);
-- New keys only. T3 / T4 updates re-deliver existing keys → 0 rows inserted.

/* ── HUB_ORDER ─────────────────────────────────────────────────────────── */
INSERT INTO [raw_vault].[HUB_ORDER]
    (ORDER_HK, ORDER_NUMBER, LOAD_DTS, REC_SRC)
SELECT DISTINCT
    HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.ORDER_NUMBER)))),
    s.ORDER_NUMBER,
    s.LOAD_DTS,
    s.REC_SRC
FROM [staging].[STG_ORDERS] s
WHERE NOT EXISTS (
    SELECT 1
    FROM [raw_vault].[HUB_ORDER] h
    WHERE h.ORDER_HK = HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.ORDER_NUMBER))))
);

/* ── HUB_PRODUCT ───────────────────────────────────────────────────────── */
INSERT INTO [raw_vault].[HUB_PRODUCT]
    (PRODUCT_HK, PRODUCT_CODE, LOAD_DTS, REC_SRC)
SELECT DISTINCT
    HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.PRODUCT_CODE)))),
    s.PRODUCT_CODE,
    s.LOAD_DTS,
    s.REC_SRC
FROM [staging].[STG_ORDERS] s
WHERE NOT EXISTS (
    SELECT 1
    FROM [raw_vault].[HUB_PRODUCT] h
    WHERE h.PRODUCT_HK = HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.PRODUCT_CODE))))
);

/* ============================================================================
   HUB DESIGN NOTES
   ----------------
   1. DISTINCT on the stage — a batch may contain the same key multiple times.
   2. NOT EXISTS guard — idempotent: replaying the same batch never duplicates.
   3. Hash recipe must be IDENTICAL everywhere (same casing, same trimming,
      same algorithm). Standardise in a staging computed column or a scalar
      function so it cannot drift between Hub and Link loads.
   4. LOAD_DTS records FIRST seen — never updated if the key re-appears.
   5. REC_SRC records which source was first to report this key.
   6. Run all Hubs in PARALLEL before loading any Links — Links need Hub HKs.
============================================================================ */
