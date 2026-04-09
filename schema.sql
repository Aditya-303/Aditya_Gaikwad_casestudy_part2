-- ============================================================
--  Inventory Management System — Database Schema
--  Designed for: Multi-warehouse, multi-company inventory
-- ============================================================


-- ============================================================
--  COMPANIES
--  Top-level tenant. Every warehouse and product catalog
--  belongs to a company.
-- ============================================================
CREATE TABLE companies (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name            VARCHAR(255) NOT NULL,
  legal_name      VARCHAR(255),
  tax_id          VARCHAR(100),
  country_code    CHAR(2)     NOT NULL,
  is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
--  WAREHOUSES
--  A company can have multiple warehouses.
-- ============================================================
CREATE TABLE warehouses (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID        NOT NULL REFERENCES companies(id),
  name            VARCHAR(255) NOT NULL,
  address_line1   VARCHAR(255),
  city            VARCHAR(100),
  country_code    CHAR(2)     NOT NULL,
  timezone        VARCHAR(50) NOT NULL DEFAULT 'UTC',
  is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_warehouses_company ON warehouses(company_id);


-- ============================================================
--  PRODUCTS
--  Global product catalog. is_bundle = TRUE means this
--  product is composed of other products (see bundle_items).
-- ============================================================
CREATE TABLE products (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  sku             VARCHAR(100) NOT NULL UNIQUE,
  name            VARCHAR(255) NOT NULL,
  description     TEXT,
  unit_of_measure VARCHAR(50) NOT NULL DEFAULT 'each',
  is_bundle       BOOLEAN     NOT NULL DEFAULT FALSE,
  is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
  weight_kg       NUMERIC(8,3),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
--  WAREHOUSE_INVENTORY
--  Current stock level for a product in a specific warehouse.
--  One row per (warehouse, product) pair.
-- ============================================================
CREATE TABLE warehouse_inventory (
  id                  UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id        UUID  NOT NULL REFERENCES warehouses(id),
  product_id          UUID  NOT NULL REFERENCES products(id),
  quantity_on_hand    INT   NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
  quantity_reserved   INT   NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
  reorder_point       INT   NOT NULL DEFAULT 0,
  last_updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (warehouse_id, product_id)
);

CREATE INDEX idx_wi_warehouse ON warehouse_inventory(warehouse_id);
CREATE INDEX idx_wi_product   ON warehouse_inventory(product_id);


-- ============================================================
--  INVENTORY_LEDGER
--  Append-only audit trail. Every stock change writes one row.
--  Never update or delete rows in this table.
--
--  quantity_delta : positive = stock in, negative = stock out
--  quantity_after : snapshot of quantity_on_hand after change
--  change_reason  : e.g. 'purchase_order', 'sale', 'adjustment',
--                   'damage', 'inter_warehouse_transfer'
--  reference_id   : polymorphic FK (PO id, order id, etc.)
--  reference_type : 'purchase_order' | 'sales_order' | 'adjustment'
-- ============================================================
CREATE TABLE inventory_ledger (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_inventory_id  UUID        NOT NULL REFERENCES warehouse_inventory(id),
  quantity_delta          INT         NOT NULL,
  quantity_after          INT         NOT NULL,
  change_reason           VARCHAR(100) NOT NULL,
  changed_by_user_id      UUID,                    -- FK to users table (to be defined)
  reference_id            UUID,
  reference_type          VARCHAR(50),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ledger_wi_id      ON inventory_ledger(warehouse_inventory_id);
CREATE INDEX idx_ledger_created_at ON inventory_ledger(created_at);


-- ============================================================
--  SUPPLIERS
--  Independent supplier entities. Not owned by any company —
--  companies opt-in via company_suppliers.
-- ============================================================
CREATE TABLE suppliers (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name            VARCHAR(255) NOT NULL,
  contact_email   VARCHAR(255),
  country_code    CHAR(2),
  is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
--  COMPANY_SUPPLIERS
--  Which suppliers are approved for which companies.
--  status: 'pending' | 'approved' | 'suspended'
-- ============================================================
CREATE TABLE company_suppliers (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID        NOT NULL REFERENCES companies(id),
  supplier_id     UUID        NOT NULL REFERENCES suppliers(id),
  status          VARCHAR(20) NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'approved', 'suspended')),
  approved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, supplier_id)
);


-- ============================================================
--  SUPPLIER_PRODUCTS
--  Which products a supplier can provide, at what cost
--  and lead time. is_preferred flags the default supplier
--  for a given product.
-- ============================================================
CREATE TABLE supplier_products (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id     UUID          NOT NULL REFERENCES suppliers(id),
  product_id      UUID          NOT NULL REFERENCES products(id),
  supplier_sku    VARCHAR(100),
  unit_cost       NUMERIC(12,4) NOT NULL,
  currency_code   CHAR(3)       NOT NULL DEFAULT 'USD',
  lead_time_days  INT,
  is_preferred    BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (supplier_id, product_id)
);

CREATE INDEX idx_supplier_products_product ON supplier_products(product_id);


-- ============================================================
--  BUNDLE_ITEMS
--  Self-referential: maps a bundle product to its components.
--  A bundle can contain multiple components, each with a qty.
--  Constraint prevents a product from being its own component.
--  NOTE: Application layer must guard against circular bundles.
-- ============================================================
CREATE TABLE bundle_items (
  id                    UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
  bundle_product_id     UUID  NOT NULL REFERENCES products(id),
  component_product_id  UUID  NOT NULL REFERENCES products(id),
  quantity              INT   NOT NULL CHECK (quantity > 0),
  CHECK (bundle_product_id <> component_product_id),
  UNIQUE (bundle_product_id, component_product_id)
);

CREATE INDEX idx_bundle_items_bundle    ON bundle_items(bundle_product_id);
CREATE INDEX idx_bundle_items_component ON bundle_items(component_product_id);


-- ============================================================
--  END OF SCHEMA
-- ============================================================
