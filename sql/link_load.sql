/* ============================================================================
   LINK LOAD PATTERN — Data Vault 2.0
   Insert unique key combinations never seen before. Idempotent.
   Written for SQL Server (T-SQL).

   Key rule: the composite hash of ALL Hub keys forms the Link PK.
   LOAD_DTS is an attribute — NOT part of the primary key.
============================================================================ */

/* ── LNK_ORDER_ITEM (Order × Product × Customer) ───────────────────────── */
INSERT INTO [raw_vault].[LNK_ORDER_ITEM]
    (ORDER_ITEM_HK, ORDER_HK, PRODUCT_HK, CUSTOMER_HK, LOAD_DTS, REC_SRC)
SELECT DISTINCT
    /* Composite hash — concat all business keys in a fixed order, pipe-delimited */
    HASHBYTES('SHA2_256',
        UPPER(LTRIM(RTRIM(s.ORDER_NUMBER)))   + '|' +
        UPPER(LTRIM(RTRIM(s.PRODUCT_CODE)))   + '|' +
        UPPER(LTRIM(RTRIM(s.CUSTOMER_NUMBER)))
    )                                                   AS ORDER_ITEM_HK,
    HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.ORDER_NUMBER))))    AS ORDER_HK,
    HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.PRODUCT_CODE))))    AS PRODUCT_HK,
    HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.CUSTOMER_NUMBER)))) AS CUSTOMER_HK,
    s.LOAD_DTS,
    s.REC_SRC
FROM [staging].[STG_ORDERS] s
WHERE NOT EXISTS (
    SELECT 1
    FROM [raw_vault].[LNK_ORDER_ITEM] l
    WHERE l.ORDER_ITEM_HK = HASHBYTES('SHA2_256',
        UPPER(LTRIM(RTRIM(s.ORDER_NUMBER)))   + '|' +
        UPPER(LTRIM(RTRIM(s.PRODUCT_CODE)))   + '|' +
        UPPER(LTRIM(RTRIM(s.CUSTOMER_NUMBER)))
    )
);
-- Re-running the same batch: identical composite hash → NOT EXISTS fires → 0 rows.

/* ── LNK_ORDER_PAYMENT (Order × Payment Method) ────────────────────────── */
INSERT INTO [raw_vault].[LNK_ORDER_PAYMENT]
    (ORDER_PAYMENT_HK, ORDER_HK, PAYMENT_METHOD_HK, LOAD_DTS, REC_SRC)
SELECT DISTINCT
    HASHBYTES('SHA2_256',
        UPPER(LTRIM(RTRIM(s.ORDER_NUMBER)))      + '|' +
        UPPER(LTRIM(RTRIM(s.PAYMENT_METHOD_CODE)))
    )                                                        AS ORDER_PAYMENT_HK,
    HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.ORDER_NUMBER))))         AS ORDER_HK,
    HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(s.PAYMENT_METHOD_CODE))))  AS PAYMENT_METHOD_HK,
    s.LOAD_DTS,
    s.REC_SRC
FROM [staging].[STG_PAYMENTS] s
WHERE NOT EXISTS (
    SELECT 1
    FROM [raw_vault].[LNK_ORDER_PAYMENT] l
    WHERE l.ORDER_PAYMENT_HK = HASHBYTES('SHA2_256',
        UPPER(LTRIM(RTRIM(s.ORDER_NUMBER)))      + '|' +
        UPPER(LTRIM(RTRIM(s.PAYMENT_METHOD_CODE)))
    )
);

/* ============================================================================
   LINK DESIGN NOTES
   -----------------
   1. Composite hash recipe: ALWAYS the same business keys in the SAME ORDER,
      with the SAME delimiter and SAME casing/trimming. Document this recipe.
   2. A Link records ONLY that the relationship EXISTS — no amounts, no dates,
      no status. All of that lives in Link Satellites (SAT_ attached to the LNK_).
   3. Links are never temporal: no EFFECTIVE_FROM / EFFECTIVE_TO here.
      Validity → Effectivity Satellite. Status → descriptive Satellite.
   4. Run Links in PARALLEL after all Hubs complete (Hub HKs must exist first).
   5. Granularity is set by which Hub keys you include. More keys = finer grain.
      Model at the lowest granularity you will ever need.
   6. The same composite key appearing twice from different sources = 0 rows;
      the duplicate is simply absorbed. REC_SRC records who was first.
============================================================================ */
