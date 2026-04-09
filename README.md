# Aditya_Gaikwad_casestudy_part2
# Inventory Management — Database Design

## Overview
Schema design for a multi-warehouse inventory management system.

## Tables
- `companies` — top-level tenants
- `warehouses` — per-company storage locations
- `products` — product catalog with bundle support
- `warehouse_inventory` — current stock levels
- `inventory_ledger` — append-only audit trail of all changes
- `suppliers` / `company_suppliers` — supplier relationships
- `supplier_products` — pricing and lead times
- `bundle_items` — self-referential product bundles

## Files
| File | Description |
|------|-------------|
| `schema.sql` | Full DDL with tables, constraints, indexes |
| `DESIGN_DECISIONS.md` | Design rationale and open questions |

## How to Run
```sql
psql -U youruser -d yourdb -f schema.sql
```
