# Link Rules — 5.0

Governing rules for designing and loading Links.

---

## 5.1 — Must Contain Two or More Hub Keys

A Link must import at least two Hub primary keys. A Link can never depend on another Link — only on Hubs.

## 5.2 — Hierarchical Link Uses Same Hub Twice

For parent-child relationships within the same entity type, the same Hub key is imported twice — once as parent and once as child.

| Column | Role |
|--------|------|
| `parent_product_hk` | FK to `HUB_PRODUCT` — the parent bundle |
| `child_product_hk` | FK to `HUB_PRODUCT` again — the child item |

## 5.3 — Link Load Date is an Attribute, Never Part of PK

The composite of all imported Hub keys forms the Link PK. `LOAD_DTS` is never part of it.

## 5.4 — Link Composite Key Must Be Unique

One row per unique combination of business keys, valid for ALL TIME. The same combination arriving again → zero rows inserted.

## 5.5 — Link Surrogate Key is Optional

If the composite key is too large or performs poorly, a single surrogate hash key can replace them as the PK.

## 5.6 & 5.10 — Granularity

Always model at the **lowest level of granularity** for maximum tracking capability. More Hub keys = finer grain.

| Keys | Granularity |
|------|-------------|
| Customer + Order | Coarse |
| Customer + Product + Order | Medium |
| Customer + Product + Order + Store | Finest |

## 5.7 — Can Represent a Transaction, Hierarchy, or Relationship

| Link Type | Hub Keys | Example |
|-----------|----------|---------|
| Relationship | Customer + Product | Customers who bought a product |
| Transaction | Customer + Product + Order + Date | A completed purchase event |
| Hierarchy | Same Hub twice | Product item in a product bundle |

## 5.9 & 5.11 — Never Temporal, One Instance For All Time

Links never contain begin/end dates. A Link records that a relationship EXISTS — not WHEN it was active. Temporality belongs in **Effectivity Satellites**.

| Link | Effectivity Satellite |
|------|-----------------------|
| Fact that the relationship exists | When it was active / inactive |

## 5.13 — Driving Key Rule

The driving key is the consistent owner of the relationship — the part that stays constant while other parts change.

| Scenario | Driving Key | Non-Driving Key |
|----------|------------|-----------------|
| Salesperson reassigned from Account A → B | Account (stays constant) | Salesperson (changed) |
| Order updated from Product X → Y | Customer + Order | Product (changed) |
