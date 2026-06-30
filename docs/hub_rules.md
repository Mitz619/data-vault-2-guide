# Hub Rules — 4.0

Governing rules for designing and loading Hubs. Every Hub must comply with all applicable rules.

---

## 4.1 — Must Have at Least One Business Key

Every Hub must have at least one business key field. Without a business key there is nothing to identify the entity.

| Valid | Invalid |
|-------|---------|
| `HUB_CUSTOMER` with `customer_number` as the business key | A table with only a hash key and load date — no business key means no entity identity |

## 4.2 — Business Key to Surrogate is One-to-One

If a hash key or sequence surrogate is used it must be one-to-one with the business key.

## 4.3 — Cannot Contain Multiple Stand-Alone Business Keys

If two business keys are independently meaningful they cannot live in the same Hub. Each gets its own Hub, connected by a Link.

| Wrong | Correct |
|-------|---------|
| One Hub with both `customer_number` AND `invoice_number` | `HUB_CUSTOMER` + `HUB_INVOICE` + `LINK_CUSTOMER_INVOICE` |

## 4.4 — Should Have at Least One Satellite

A Hub without any Satellite has no context. A **Stub Hub** is the correct pattern when detail is temporarily out of scope.

| State | Meaning |
|-------|---------|
| Hub with Satellites | Complete |
| Hub without Satellites — Stub Hub | Placeholder — detail out of scope this sprint |
| Hub without Satellites permanently | Problem — likely missing source or scope |

## 4.5 — Composite Key When Source Systems Collide

A single Hub can have a composite business key only when two source systems use identical key values to mean completely different things. The source system name becomes part of the composite.

## 4.6 — Business Key Stands Alone

The business key must be independently meaningful.

| Key Type | Qualifies? |
|----------|-----------|
| `CUST-10045` — used by the business | ✅ Yes |
| `INV-0099` printed on all invoices | ✅ Yes |
| Auto-increment DB row ID never shown to users | ❌ No |

## 4.7 — Load Date is an Attribute, Never Part of Hub PK

The Hub load date records the FIRST time the business key arrived. If it were in the PK, the same key arriving on two different days would create two Hub rows for the same entity.

## 4.8 — Record Source is NOT Part of Hub PK

If two source systems report the same customer it is still ONE customer — the Hub gets one row. Record source records which system was first to report it.
