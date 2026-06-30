# Naming Conventions — Data Vault 2.0

Consistent naming is **mandatory** for ETL automation. Without it, every Hub, Link, and Satellite must be hand-coded rather than auto-generated.

> ⚠️ The prefixes/suffixes below are recommendations from the DV 2.0 specification. What IS required is that you create and maintain a naming convention document specific to YOUR implementation and apply it consistently.

---

## Table Naming

### Entity Prefixes

| Entity | Prefix | Example |
|--------|--------|---------|
| Hub | `HUB_` | `HUB_CUSTOMER` |
| Link | `LNK_` | `LNK_ORDER_ITEM` |
| Satellite | `SAT_` | `SAT_CUSTOMER_PROFILE` |
| Hierarchical Link | `HLNK_` | `HLNK_PRODUCT_BUNDLE` |
| Same-As Link | `SAL_` | `SAL_CUSTOMER_MASTER` |
| Point-in-Time | `PIT_` | `PIT_CUSTOMER` |
| Bridge | `BRDG_` | `BRDG_ORDER_SALES` |
| Business Hub | `BHUB_` | `BHUB_CUSTOMER_CLEANSED` |
| Business Link | `BLNK_` | `BLNK_ORDER_ENRICHED` |
| Business Satellite | `BSAT_` | `BSAT_CUSTOMER_SCORED` |
| Staging | `STG_` | `STG_CRM_CUSTOMERS` |
| Reporting Table | `RPT_` | `RPT_MONTHLY_SALES` |
| Fact View | `VF_` / `FCT_` | `VF_SALES`, `FCT_REVENUE` |
| Dimension View | `VDIM_` / `DIM_` | `VDIM_CUSTOMER`, `DIM_DATE` |

---

## Field Naming

### Required Suffixes

| Attribute | Suffix | Example |
|-----------|--------|---------|
| Hash Key | `_HK` | `CUSTOMER_HK`, `ORDER_HK` |
| Hash Difference | `HASH_DIFF` or `_HD` | `HASH_DIFF`, `CONTACT_HD` |
| Load Date Timestamp | `LOAD_DTS` | `LOAD_DTS` |
| Record Source | `REC_SRC` | `REC_SRC` |
| Sub-Sequence | `_SSQN` | `ADDRESS_SSQN` |
| Snapshot Timestamp | `SNAPSHOT_DTS` | `SNAPSHOT_DTS` |
| Applied Date | `_APPDT` | `TRANSACTION_APPDT` |

---

## Field Naming Within Tables

### Audit Columns (on every table, every row)

```sql
LOAD_DTS    DATETIME2    -- When the vault received this row
REC_SRC     VARCHAR(50)  -- Which source system produced it
```

### Satellite-only

```sql
HASH_DIFF   BINARY(16)   -- Hash of all payload columns for change detection
```

### Multi-Active Satellite

```sql
<parent>_HK (PK, FK)  -- From parent Hub or Link
LOAD_DTS    (PK)       -- Load timestamp
SSQN        (PK)       -- Sub-sequence: natural sub-key from source
```

---

## Casing Convention

Use `UPPER_SNAKE_CASE` for all object and column names. This matches the DV 2.0 specification and most SQL Server / ETL tool conventions.

---

## Hash Key Recipe — Standardise and Document

The hash recipe must be **identical everywhere**. A suggested standard:

```sql
-- SQL Server
HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(business_key_col))))

-- Composite (multiple business keys)
HASHBYTES('SHA2_256',
    UPPER(LTRIM(RTRIM(key1))) + '|' +
    UPPER(LTRIM(RTRIM(key2))) + '|' +
    UPPER(LTRIM(RTRIM(key3)))
)
```

Standardise the recipe in a staging computed column or a scalar function. If the recipe drifts between Hub and Link loads, the same business entity produces different hash keys — breaking all joins.

---

## What NOT to Do

| ❌ Don't | ✅ Do instead |
|----------|--------------|
| Mix prefixes (`hub_` vs `HUB_`) | Pick one and apply it everywhere |
| Use auto-increment IDs as HKs | Use deterministic hash keys |
| Name a FK differently from its PK | `CUSTOMER_HK` in Hub = `CUSTOMER_HK` in Link and Satellite |
| Store descriptive data in a Hub or Link | Move it to a Satellite |
| Store relationship FKs in a Satellite | Move them to a Link |
