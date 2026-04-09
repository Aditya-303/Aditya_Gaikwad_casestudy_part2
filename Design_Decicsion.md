# Design Decisions, Gaps & Open Questions

## Table of Contents
1. [Key Design Decisions](#key-design-decisions)
2. [Gaps — Questions for the Product Team](#gaps--questions-for-the-product-team)
3. [Assumptions Made](#assumptions-made)

---

## Key Design Decisions

### 1. UUID Primary Keys over Serial Integers
- Avoids leaking row counts to external clients
- Safe for distributed inserts across multiple services
- Makes cross-database merges and data migrations trivial
- Minor index-size cost is acceptable for the benefits gained

### 2. Separate `warehouse_inventory` (current state) and `inventory_ledger` (history)
This is the most important design decision in the schema.

| Table | Purpose |
|-------|---------|
| `warehouse_inventory` | Single row per (warehouse, product) — gives O(1) lookup for current stock |
| `inventory_ledger` | Append-only, never updated or deleted — full audit trail of every change |

Keeping these separate follows a CQRS-lite pattern common in inventory systems:
- Reads for current stock hit the small, indexed `warehouse_inventory` table
- Historical queries and audits hit the ledger without impacting live operations
- The ledger is immutable — no UPDATE or DELETE ever runs on it

### 3. `quantity_delta` + `quantity_after` stored together in the ledger
Storing both fields means:
- You can reconstruct state by scanning deltas forward from any point
- You can use any `quantity_after` as a checkpoint to avoid full table scans
- Data corruption is detectable by recalculating `quantity_after` from deltas

### 4. `reorder_point` lives on `warehouse_inventory`, not `products`
Reorder thresholds are warehouse-specific in real operations:
- A main distribution center holds more safety stock than a small satellite warehouse
- Different warehouses may serve different demand volumes
- Placing it on the product would force a single global threshold

### 5. Suppliers are independent entities, not owned by a company
Suppliers connect to companies via the `company_suppliers` junction table instead of having a `company_id` foreign key directly. This means:
- The same physical supplier appears once in the system (no duplicates)
- Cross-company supplier reporting is possible
- A supplier can be approved for some companies and pending for others
- Supplier contact data is maintained in one place

### 6. `bundle_items` as a self-referential join on `products`
Rather than a separate bundles table, bundles are modeled as a self-join:
- Simpler schema — one less table
- The `is_bundle` flag on `products` is a denormalized convenience to filter bundles without a join
- `CHECK (bundle_product_id <> component_product_id)` prevents a product referencing itself
- The `UNIQUE (bundle_product_id, component_product_id)` constraint prevents duplicate components

> **Note:** The application layer must guard against circular bundle references (e.g., Product A contains Product B which contains Product A). This cannot be enforced at the DB constraint level in standard SQL.

### 7. Polymorphic reference on `inventory_ledger`
The `reference_id` + `reference_type` pair allows the ledger to point to different source documents (purchase orders, sales orders, manual adjustments) without separate FK columns for each:
- Flexible — new reference types can be added without schema changes
- Trade-off: referential integrity is not enforced at the DB level for this column
- Application layer is responsible for ensuring valid `reference_id` values

### 8. Indexes chosen for common query patterns

| Index | Reason |
|-------|--------|
| `idx_warehouses_company` | Look up all warehouses for a company |
| `idx_wi_warehouse` | Look up all inventory rows for a warehouse |
| `idx_wi_product` | Look up all warehouses stocking a product |
| `idx_ledger_wi_id` | Fetch history for a specific inventory row |
| `idx_ledger_created_at` | Time-range queries on inventory changes |
| `idx_supplier_products_product` | Find all suppliers for a given product |
| `idx_bundle_items_bundle` | Fetch all components of a bundle |
| `idx_bundle_items_component` | Find all bundles containing a component |

---

## Gaps — Questions for the Product Team

### Products & SKUs
- Are SKUs global across all companies, or does each company maintain its own product catalog? If multi-tenant catalogs are needed, `products` needs a `company_id` foreign key.
- Can a bundle contain other bundles (nested bundles)? The schema allows it structurally but the application needs a cycle-detection guard.
- What triggers a product to be "archived"? Are there compliance or audit requirements when deactivating a product that still has inventory?

### Inventory & Stock Tracking
- What are the exact change reason types? The `change_reason` field needs a defined enum matching real business workflows — e.g., `purchase_order_receipt`, `sales_order_fulfillment`, `damage_writeoff`, `inter_warehouse_transfer`, `cycle_count_adjustment`.
- Is there a concept of **lots or batches** (expiry dates, serial numbers, batch codes)? If yes, `warehouse_inventory` needs a lot/batch dimension and the schema changes significantly.
- What does **"reserved"** quantity mean exactly — is it tied to open sales orders? If so, reservations need to be released when orders are fulfilled or cancelled, requiring an orders table.
- Do **inter-warehouse transfers** need to be tracked as atomic two-sided events (decrement warehouse A, increment warehouse B in a single transaction)?
- Is there a concept of **negative inventory** (backorders)? The current `CHECK (quantity_on_hand >= 0)` prevents it — should it?

### Suppliers
- Can a supplier offer **different prices to different companies** (contract pricing)? If yes, `unit_cost` needs to move from `supplier_products` to a `company_supplier_products` table.
- Who manages the supplier catalog — is it centralized by a platform admin, or can each company onboard their own suppliers independently?
- Is there a **purchase order** concept that links supplier → warehouse → product receipt? If yes, that is a major missing table.

### Users & Permissions
- The schema references `changed_by_user_id` in `inventory_ledger` but there is no `users` table in the requirements. Who are the actors making inventory changes — humans, automated systems, or both?
- Is there a **roles and permissions model**? (e.g., warehouse manager vs company admin vs read-only auditor)

### Multi-tenancy
- Are products, warehouses, and suppliers **fully isolated per company**, or is there a shared product master catalog that multiple companies subscribe to?
- Can a user belong to **multiple companies**?

---

## Assumptions Made

Since the requirements were intentionally incomplete, the following assumptions were made to proceed with the design:

| Assumption | Rationale |
|------------|-----------|
| SKUs are globally unique across all companies | Simplest starting point; can be scoped to company later |
| Negative inventory is not allowed | Most inventory systems enforce this; flagged as a gap |
| A single currency per supplier-product row | Multi-currency pricing requires a separate exchange rate table |
| Users table exists but is out of scope | `changed_by_user_id` is included as a placeholder UUID |
| Nested bundles are allowed | No requirement said otherwise; cycle guard is application-level |
| Reorder alerts are out of scope | `reorder_point` is stored but notification logic is application-level |

---

*Schema version: 1.0 — Initial design for review*
