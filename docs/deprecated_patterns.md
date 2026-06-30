# Deprecated Patterns in Data Vault 2.0

These rules were part of Data Vault 1.0 and have been **removed from DV 2.0**. Never use them in new designs.

---

## ❌ 10.1 — Sequence ID Surrogate Keys

Auto-incrementing integer surrogate keys (`IDENTITY` columns) were the original DV 1.0 primary key approach.

**Why they fail:**

| Problem | Detail |
|---------|--------|
| Row-by-row lookup required | To insert a child row you must first look up the parent sequence ID — sequential, cannot be parallelised |
| Non-deterministic | Two parallel ETL processes may assign different IDs to the same key — creating duplicates |
| Cross-geography conflicts | Sequence IDs from different regions conflict when integrating |
| Privacy compliance | Clear-text business keys cross country borders for lookup — violates data sovereignty |

**DV 2.0 solution:** Hash keys (`MD5` / `SHA-256`) computed deterministically from the business key. Any ETL process computes the same hash independently — no central lookup, no conflicts.

> ❌ **NEVER** use auto-increment sequence IDs as primary keys in Data Vault 2.0.

---

## ❌ 10.2 — Satellite Load End-Dates

In DV 1.0, each Satellite row had a `load_end_date` column that was physically `UPDATE`d when a newer version arrived.

**Why it fails:**

| Problem | Detail |
|---------|--------|
| Requires `UPDATE` statements | Not scalable at large data volumes; breaks insert-only architecture |
| Out-of-order data | Late-arriving feeds produce incorrect end dates |
| Not idempotent | Replaying a batch sets wrong end dates on existing rows |

**DV 2.0 solution:** No `load_end_date` in the Raw Vault. Compute end dates at query time using SQL `LEAD()` window functions, or materialise them in PIT / Bridge tables in the Information Mart.

```sql
-- Compute end-date at query time using LEAD
SELECT
    CUSTOMER_HK,
    LOAD_DTS                                              AS effective_from,
    LEAD(LOAD_DTS) OVER (
        PARTITION BY CUSTOMER_HK ORDER BY LOAD_DTS
    )                                                     AS effective_to,
    EMAIL_ADDRESS
FROM raw_vault.SAT_CUSTOMER_PROFILE;
```

> ❌ **NEVER** add a `load_end_date` column to Raw Vault Satellites.

---

## ❌ 10.3 — Hub and Link Last-Seen Dates

Early versions of Data Vault added a `last_seen_date` column to Hubs and Links that was `UPDATE`d each time the key or relationship was re-observed.

**Why it fails:** Same root cause as end-dates — requires physical `UPDATE` statements that do not scale and can corrupt the timeline with out-of-order data.

**DV 2.0 solution:** Use Effectivity Satellites to track when a business key or relationship was active or last observed.

> ❌ **NEVER** add `last_seen_date` columns to Hubs or Links in Data Vault 2.0.

---

## Root Cause: All Three Require Physical Updates

```text
DV 2.0 is an INSERT-ONLY architecture.
No row in the Raw Vault is ever physically modified after it is inserted.
```

This is what makes Data Vault 2.0 fully auditable, parallelisable, and scalable to any data volume. The three deprecated patterns all broke this guarantee — which is why they were removed.
