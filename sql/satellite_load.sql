/* ============================================================================
   SATELLITE LOAD PATTERN — Data Vault 2.0
   Insert a new row ONLY when HASH_DIFF changes. Idempotent.
   Written for SQL Server (T-SQL).

   HASH_DIFF = hash of all descriptive (payload) columns.
   Compare staged HASH_DIFF to the most recent stored HASH_DIFF:
     • Different → insert new version row
     • Same      → skip (idempotent; no duplicate version)
============================================================================ */

/* ── SAT_CUSTOMER_PROFILE (parent: HUB_CUSTOMER) ───────────────────────── */
WITH staged AS (
    SELECT
        HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(CUSTOMER_NUMBER)))) AS CUSTOMER_HK,
        LOAD_DTS,
        /* HASH_DIFF: pipe-delimited concat of all payload columns in fixed order */
        HASHBYTES('SHA2_256',
            ISNULL(FULL_NAME,       '') + '|' +
            ISNULL(EMAIL_ADDRESS,   '') + '|' +
            ISNULL(PHONE_NUMBER,    '') + '|' +
            ISNULL(LOYALTY_TIER,    '')
        )                                   AS HASH_DIFF,
        REC_SRC,
        FULL_NAME,
        EMAIL_ADDRESS,
        PHONE_NUMBER,
        LOYALTY_TIER
    FROM [staging].[STG_CUSTOMERS]
),
latest_stored AS (
    /* Most recent stored version per customer, for comparison */
    SELECT
        CUSTOMER_HK,
        HASH_DIFF,
        LOAD_DTS,
        ROW_NUMBER() OVER (PARTITION BY CUSTOMER_HK ORDER BY LOAD_DTS DESC) AS rn
    FROM [raw_vault].[SAT_CUSTOMER_PROFILE]
)
INSERT INTO [raw_vault].[SAT_CUSTOMER_PROFILE]
    (CUSTOMER_HK, LOAD_DTS, HASH_DIFF, REC_SRC,
     FULL_NAME, EMAIL_ADDRESS, PHONE_NUMBER, LOYALTY_TIER)
SELECT
    s.CUSTOMER_HK,
    s.LOAD_DTS,
    s.HASH_DIFF,
    s.REC_SRC,
    s.FULL_NAME,
    s.EMAIL_ADDRESS,
    s.PHONE_NUMBER,
    s.LOYALTY_TIER
FROM staged s
LEFT JOIN latest_stored ls
    ON  ls.CUSTOMER_HK = s.CUSTOMER_HK
    AND ls.rn = 1
WHERE
    /* New key with no existing satellite rows */
    ls.CUSTOMER_HK IS NULL
    /* OR descriptive attributes have changed */
    OR ls.HASH_DIFF <> s.HASH_DIFF;

/* ── SAT_ORDER_STATUS (parent: LNK_ORDER_ITEM) ──────────────────────────── */
WITH staged AS (
    SELECT
        /* Recompute the same composite hash used in the Link load */
        HASHBYTES('SHA2_256',
            UPPER(LTRIM(RTRIM(ORDER_NUMBER)))   + '|' +
            UPPER(LTRIM(RTRIM(PRODUCT_CODE)))   + '|' +
            UPPER(LTRIM(RTRIM(CUSTOMER_NUMBER)))
        )                                               AS ORDER_ITEM_HK,
        LOAD_DTS,
        HASHBYTES('SHA2_256',
            ISNULL(ORDER_STATUS,    '') + '|' +
            ISNULL(DELIVERY_STATUS, '') + '|' +
            ISNULL(TRACKING_NUMBER, '')
        )                                               AS HASH_DIFF,
        REC_SRC,
        ORDER_STATUS,
        DELIVERY_STATUS,
        TRACKING_NUMBER,
        EST_DELIVERY_DATE
    FROM [staging].[STG_ORDER_UPDATES]
),
latest_stored AS (
    SELECT
        ORDER_ITEM_HK,
        HASH_DIFF,
        ROW_NUMBER() OVER (PARTITION BY ORDER_ITEM_HK ORDER BY LOAD_DTS DESC) AS rn
    FROM [raw_vault].[SAT_ORDER_STATUS]
)
INSERT INTO [raw_vault].[SAT_ORDER_STATUS]
    (ORDER_ITEM_HK, LOAD_DTS, HASH_DIFF, REC_SRC,
     ORDER_STATUS, DELIVERY_STATUS, TRACKING_NUMBER, EST_DELIVERY_DATE)
SELECT
    s.ORDER_ITEM_HK,
    s.LOAD_DTS,
    s.HASH_DIFF,
    s.REC_SRC,
    s.ORDER_STATUS,
    s.DELIVERY_STATUS,
    s.TRACKING_NUMBER,
    s.EST_DELIVERY_DATE
FROM staged s
LEFT JOIN latest_stored ls
    ON  ls.ORDER_ITEM_HK = s.ORDER_ITEM_HK
    AND ls.rn = 1
WHERE ls.ORDER_ITEM_HK IS NULL
   OR ls.HASH_DIFF <> s.HASH_DIFF;

/* ============================================================================
   SATELLITE DESIGN NOTES
   ----------------------
   1. HASH_DIFF covers ALL payload columns in a FIXED, DOCUMENTED order.
      NULL-safe: ISNULL(col, '') prevents NULL-driven hash differences.
   2. The load compares only the LATEST stored version (ROW_NUMBER rn=1).
      Replaying an old batch: same HASH_DIFF → 0 rows. Idempotent.
   3. Never UPDATE or DELETE satellite rows. A "correction" is a new row.
   4. LOAD_DTS is part of the PK together with the parent HK.
      Two updates to the same key in the same microsecond → add a
      SUB_SEQUENCE column to break the tie (multi-active satellites).
   5. Split fast-changing and slow-changing attributes into SEPARATE satellites
      to prevent unnecessary row proliferation (e.g. stock level vs product name).
   6. Run Satellite loads AFTER the corresponding Hub/Link loads complete
      (parent HK must exist before child rows are inserted).
   7. For multi-active satellites (e.g. sessions, segments) the PK includes
      the sub-sequence: (parent_HK, LOAD_DTS, SSQN). The SSQN is typically
      a natural sub-key from the source (participantId|sessionId).
============================================================================ */
