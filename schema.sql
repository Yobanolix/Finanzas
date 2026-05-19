-- ============================================================
-- WEALTH OS — Postgres schema (v2)
-- Single-tenant. Sin user_id por diseño (ver ADR-001).
-- Convenciones:
--   * IDs: BIGSERIAL para auto-increment
--   * Money: BIGINT en unidad mínima (CLP entero, USD centavos, UF×10000)
--   * Timestamps: TIMESTAMPTZ (UTC interno; tz handling en app)
--   * Soft delete: deleted_at TIMESTAMPTZ nullable
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;       -- encriptación selectiva
CREATE EXTENSION IF NOT EXISTS pg_trgm;        -- trigram search en descripciones

-- ============================================================
-- ENUMS
-- ============================================================
CREATE TYPE currency_code AS ENUM ('CLP', 'USD', 'UF', 'EUR');
CREATE TYPE account_type AS ENUM ('checking', 'savings', 'credit', 'cash', 'brokerage');
CREATE TYPE investment_type AS ENUM ('etf', 'stock', 'mutual_fund', 'crypto', 'bond', 'commodity');
CREATE TYPE property_status AS ENUM ('primary', 'rental', 'empty', 'sold');
CREATE TYPE business_status AS ENUM ('active', 'paused', 'closed');
CREATE TYPE category_type AS ENUM ('income', 'expense', 'transfer');
CREATE TYPE ai_analysis_type AS ENUM ('monthly', 'on_demand', 'chat', 'categorization');

-- ============================================================
-- FX RATES (UF, USD, EUR diarios)
-- ============================================================
CREATE TABLE fx_rates (
  id           BIGSERIAL PRIMARY KEY,
  currency     currency_code NOT NULL,
  date         DATE NOT NULL,
  value_clp    NUMERIC(18, 4) NOT NULL,  -- value of 1 unit in CLP
  source       TEXT,                     -- 'sii.cl', 'bcentral', 'manual'
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (currency, date)
);
CREATE INDEX idx_fx_rates_date ON fx_rates (date DESC);

-- ============================================================
-- CATEGORIES (con tree via parent_id)
-- ============================================================
CREATE TABLE categories (
  id           BIGSERIAL PRIMARY KEY,
  name         TEXT NOT NULL,
  type         category_type NOT NULL,
  parent_id    BIGINT REFERENCES categories(id) ON DELETE SET NULL,
  color        TEXT,                     -- hex color
  icon         TEXT,                     -- emoji or icon key
  is_system    BOOLEAN NOT NULL DEFAULT false, -- vs user-created
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at   TIMESTAMPTZ,
  UNIQUE (name, parent_id)
);
CREATE INDEX idx_categories_type ON categories (type) WHERE deleted_at IS NULL;

-- ============================================================
-- ACCOUNTS (bancarias + brokerage + cash)
-- ============================================================
CREATE TABLE accounts (
  id                 BIGSERIAL PRIMARY KEY,
  name               TEXT NOT NULL,
  bank               TEXT,
  type               account_type NOT NULL,
  currency           currency_code NOT NULL DEFAULT 'CLP',
  current_balance    BIGINT NOT NULL DEFAULT 0,           -- en unidad mínima
  credit_limit       BIGINT,                              -- solo para TC
  -- Fintoc integration
  fintoc_link_id     TEXT,                                -- token del link
  fintoc_account_id  TEXT,                                -- id en Fintoc
  last_synced_at     TIMESTAMPTZ,
  sync_enabled       BOOLEAN NOT NULL DEFAULT false,
  -- Otros
  notes              TEXT,
  is_archived        BOOLEAN NOT NULL DEFAULT false,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at         TIMESTAMPTZ
);
CREATE INDEX idx_accounts_active ON accounts (id) WHERE deleted_at IS NULL AND is_archived = false;
CREATE INDEX idx_accounts_fintoc ON accounts (fintoc_link_id) WHERE fintoc_link_id IS NOT NULL;

-- ============================================================
-- TRANSACTIONS
-- ============================================================
CREATE TABLE transactions (
  id              BIGSERIAL PRIMARY KEY,
  account_id      BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  category_id     BIGINT REFERENCES categories(id) ON DELETE SET NULL,
  date            DATE NOT NULL,
  posted_at       TIMESTAMPTZ,                            -- fecha exacta de Fintoc
  amount          BIGINT NOT NULL,                        -- signed: + ingreso, − egreso
  currency        currency_code NOT NULL DEFAULT 'CLP',
  description     TEXT NOT NULL,
  merchant        TEXT,                                   -- normalizado
  notes           TEXT,
  -- Fintoc
  fintoc_id       TEXT UNIQUE,                            -- id único del movimiento
  raw_payload     JSONB,                                  -- payload completo
  -- Conciliación
  dedup_hash      TEXT NOT NULL,                          -- sha256(date+amount+desc)
  source          TEXT NOT NULL DEFAULT 'manual',         -- manual | csv | fintoc
  -- Categorización
  is_categorized  BOOLEAN NOT NULL DEFAULT false,
  ai_confidence   NUMERIC(4, 3),                          -- 0.000-1.000 si fue IA
  is_recurring    BOOLEAN NOT NULL DEFAULT false,
  recurring_group TEXT,                                   -- agrupador para suscripciones
  -- Soft delete
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ
);
CREATE INDEX idx_tx_date ON transactions (date DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_tx_account ON transactions (account_id, date DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_tx_category ON transactions (category_id, date DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_tx_dedup ON transactions (dedup_hash);
CREATE INDEX idx_tx_uncategorized ON transactions (id) WHERE is_categorized = false AND deleted_at IS NULL;
CREATE INDEX idx_tx_description_trgm ON transactions USING gin (description gin_trgm_ops);

-- ============================================================
-- INVESTMENTS (holdings)
-- ============================================================
CREATE TABLE investments (
  id              BIGSERIAL PRIMARY KEY,
  ticker          TEXT NOT NULL,
  name            TEXT,
  type            investment_type NOT NULL,
  broker          TEXT,
  account_id      BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
  quantity        NUMERIC(20, 8) NOT NULL,                -- soporta crypto fraccionario
  avg_cost        BIGINT NOT NULL,                        -- unidad mínima en `currency`
  current_price   BIGINT NOT NULL,                        -- precio actual en `currency`
  currency        currency_code NOT NULL DEFAULT 'USD',
  last_price_update TIMESTAMPTZ,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ
);
CREATE INDEX idx_investments_active ON investments (id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_investments_ticker_broker ON investments (ticker, broker)
  WHERE deleted_at IS NULL;

-- ============================================================
-- INVESTMENT TRANSACTIONS (buys/sells/dividends/splits)
-- ============================================================
CREATE TABLE investment_transactions (
  id              BIGSERIAL PRIMARY KEY,
  investment_id   BIGINT NOT NULL REFERENCES investments(id) ON DELETE CASCADE,
  date            DATE NOT NULL,
  type            TEXT NOT NULL CHECK (type IN ('buy','sell','dividend','split','fee')),
  quantity        NUMERIC(20, 8),
  price_per_unit  BIGINT,
  fee             BIGINT NOT NULL DEFAULT 0,
  total_amount    BIGINT NOT NULL,
  currency        currency_code NOT NULL,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_inv_tx_investment ON investment_transactions (investment_id, date DESC);

-- ============================================================
-- PROPERTIES
-- ============================================================
CREATE TABLE properties (
  id                  BIGSERIAL PRIMARY KEY,
  name                TEXT NOT NULL,
  address             TEXT,
  property_type       TEXT,                                -- 'apartment','house','land','commercial'
  status              property_status NOT NULL DEFAULT 'rental',
  -- Purchase data (siempre en UF para CL)
  purchase_date       DATE,
  purchase_value_uf   NUMERIC(12, 2),                      -- UF al momento de compra
  downpayment_clp     BIGINT,                              -- pie en CLP
  -- Current value
  current_value_uf    NUMERIC(12, 2),
  last_appraisal_date DATE,
  -- Rental
  monthly_rent_clp    BIGINT,
  monthly_expenses_clp BIGINT,                             -- gastos comunes + contribuciones + admin
  vacancy_rate        NUMERIC(5, 2) DEFAULT 0,             -- % anual estimado
  -- Otros
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at          TIMESTAMPTZ
);
CREATE INDEX idx_properties_active ON properties (id) WHERE deleted_at IS NULL;

-- ============================================================
-- MORTGAGES (separadas de propiedad porque puede haber refinanciamientos)
-- ============================================================
CREATE TABLE mortgages (
  id                  BIGSERIAL PRIMARY KEY,
  property_id         BIGINT NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  bank                TEXT,
  start_date          DATE NOT NULL,
  end_date            DATE,                                -- si está cerrada
  principal_uf        NUMERIC(12, 2) NOT NULL,
  annual_rate         NUMERIC(6, 3) NOT NULL,              -- ej 4.875 = 4.875%
  term_years          INT NOT NULL,
  monthly_payment_uf  NUMERIC(10, 4) NOT NULL,
  is_active           BOOLEAN NOT NULL DEFAULT true,
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_mortgages_property ON mortgages (property_id) WHERE is_active = true;

-- ============================================================
-- PROPERTY MOVEMENTS (gastos imputables, arriendos cobrados, mejoras)
-- ============================================================
CREATE TABLE property_movements (
  id              BIGSERIAL PRIMARY KEY,
  property_id     BIGINT NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  date            DATE NOT NULL,
  type            TEXT NOT NULL CHECK (type IN ('rent_received','expense','improvement','tax','insurance','vacancy')),
  amount          BIGINT NOT NULL,
  currency        currency_code NOT NULL DEFAULT 'CLP',
  description     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_property_mov_property_date ON property_movements (property_id, date DESC);

-- ============================================================
-- BUSINESSES
-- ============================================================
CREATE TABLE businesses (
  id                 BIGSERIAL PRIMARY KEY,
  name               TEXT NOT NULL,
  description        TEXT,
  started_date       DATE,
  status             business_status NOT NULL DEFAULT 'active',
  notes              TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at         TIMESTAMPTZ
);

CREATE TABLE business_movements (
  id              BIGSERIAL PRIMARY KEY,
  business_id     BIGINT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  date            DATE NOT NULL,
  type            TEXT NOT NULL CHECK (type IN ('revenue','cost','investment','distribution')),
  amount          BIGINT NOT NULL,
  currency        currency_code NOT NULL DEFAULT 'CLP',
  description     TEXT,
  category_id     BIGINT REFERENCES categories(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_business_mov_date ON business_movements (business_id, date DESC);

-- ============================================================
-- SCENARIOS (simulaciones guardadas para comparación)
-- ============================================================
CREATE TABLE scenarios (
  id              BIGSERIAL PRIMARY KEY,
  name            TEXT NOT NULL,
  scenario_type   TEXT NOT NULL CHECK (scenario_type IN ('auto','property','savings','business','custom')),
  inputs          JSONB NOT NULL,                          -- params del simulador
  outputs         JSONB NOT NULL,                          -- resultados calculados
  notes           TEXT,
  is_pinned       BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_scenarios_type ON scenarios (scenario_type, created_at DESC);

-- ============================================================
-- AI ANALYSES
-- ============================================================
CREATE TABLE ai_analyses (
  id              BIGSERIAL PRIMARY KEY,
  type            ai_analysis_type NOT NULL,
  period_start    DATE,
  period_end      DATE,
  model           TEXT NOT NULL,                          -- 'claude-sonnet-4-6'
  prompt_hash     TEXT,                                   -- sha256 del input para dedupe
  input_tokens    INT,
  output_tokens   INT,
  cost_usd_cents  INT,                                    -- costo aproximado en centavos USD
  -- Output estructurado (parseado del tool_use)
  summary         TEXT,
  recommendations JSONB,
  alerts          JSONB,
  metrics         JSONB,
  -- Raw
  raw_response    JSONB,                                  -- por si queremos re-procesar
  -- Conversational (para chat)
  conversation_id UUID,                                   -- agrupa mensajes de un chat
  role            TEXT,                                   -- 'user'|'assistant' si es chat
  content         TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ai_analyses_type_date ON ai_analyses (type, created_at DESC);
CREATE INDEX idx_ai_analyses_conversation ON ai_analyses (conversation_id) WHERE conversation_id IS NOT NULL;

-- ============================================================
-- AUDIT LOG (append-only, todas las mutations)
-- ============================================================
CREATE TABLE audit_log (
  id              BIGSERIAL PRIMARY KEY,
  table_name      TEXT NOT NULL,
  record_id       BIGINT NOT NULL,
  action          TEXT NOT NULL CHECK (action IN ('insert','update','delete','soft_delete','restore')),
  before          JSONB,
  after           JSONB,
  source          TEXT,                                   -- 'api','cron','migration','manual'
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_table_record ON audit_log (table_name, record_id, created_at DESC);

-- ============================================================
-- FINTOC SYNC LOG
-- ============================================================
CREATE TABLE fintoc_sync_log (
  id                 BIGSERIAL PRIMARY KEY,
  account_id         BIGINT REFERENCES accounts(id) ON DELETE CASCADE,
  started_at         TIMESTAMPTZ NOT NULL,
  finished_at        TIMESTAMPTZ,
  status             TEXT NOT NULL,                       -- 'success','partial','failed'
  movements_added    INT NOT NULL DEFAULT 0,
  movements_updated  INT NOT NULL DEFAULT 0,
  movements_skipped  INT NOT NULL DEFAULT 0,
  error_message      TEXT,
  fintoc_request_id  TEXT
);
CREATE INDEX idx_sync_log_account ON fintoc_sync_log (account_id, started_at DESC);

-- ============================================================
-- MATERIALIZED VIEWS (refresh nightly)
-- ============================================================

-- Cashflow mensual agregado
CREATE MATERIALIZED VIEW mv_monthly_cashflow AS
  SELECT date_trunc('month', date)::date AS month,
         SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS income,
         SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS expenses,
         SUM(amount) AS net,
         COUNT(*) AS tx_count
  FROM transactions
  WHERE deleted_at IS NULL
  GROUP BY date_trunc('month', date);
CREATE UNIQUE INDEX idx_mv_monthly_cashflow_month ON mv_monthly_cashflow (month);

-- Snapshot histórico de patrimonio (calculado al final del día)
CREATE TABLE mv_networth_history (
  date                     DATE PRIMARY KEY,
  cash_clp                 BIGINT NOT NULL,
  investments_clp          BIGINT NOT NULL,
  real_estate_clp          BIGINT NOT NULL,
  credit_debt_clp          BIGINT NOT NULL,
  mortgage_debt_clp        BIGINT NOT NULL,
  business_value_clp       BIGINT NOT NULL DEFAULT 0,
  total_assets_clp         BIGINT NOT NULL,
  total_liabilities_clp    BIGINT NOT NULL,
  networth_clp             BIGINT NOT NULL,
  uf_value_clp             NUMERIC(10, 2) NOT NULL,        -- UF de ese día para reconvertibilidad
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_networth_history_date ON mv_networth_history (date DESC);

-- Spending por categoría por mes
CREATE MATERIALIZED VIEW mv_category_spending AS
  SELECT date_trunc('month', t.date)::date AS month,
         c.id AS category_id,
         c.name AS category_name,
         c.type AS category_type,
         SUM(ABS(t.amount)) AS total_clp,
         COUNT(*) AS tx_count
  FROM transactions t
  LEFT JOIN categories c ON t.category_id = c.id
  WHERE t.deleted_at IS NULL
  GROUP BY date_trunc('month', t.date), c.id, c.name, c.type;
CREATE INDEX idx_mv_cat_spending_month ON mv_category_spending (month DESC, total_clp DESC);

-- ============================================================
-- FUNCTIONS (cálculos derivados como SQL functions)
-- ============================================================

-- Convertir cualquier monto a CLP a una fecha dada
CREATE OR REPLACE FUNCTION to_clp(amount BIGINT, currency currency_code, on_date DATE DEFAULT CURRENT_DATE)
RETURNS BIGINT AS $$
DECLARE
  rate NUMERIC;
BEGIN
  IF currency = 'CLP' THEN
    RETURN amount;
  END IF;
  SELECT value_clp INTO rate FROM fx_rates
    WHERE currency = to_clp.currency AND date <= on_date
    ORDER BY date DESC LIMIT 1;
  IF rate IS NULL THEN
    RAISE EXCEPTION 'No FX rate for % on or before %', currency, on_date;
  END IF;
  -- amount is in minimum unit; for USD it's cents → divide by 100; for UF it's UF×10000 → divide by 10000
  IF currency = 'USD' THEN RETURN (amount * rate / 100)::BIGINT; END IF;
  IF currency = 'UF'  THEN RETURN (amount * rate / 10000)::BIGINT; END IF;
  IF currency = 'EUR' THEN RETURN (amount * rate / 100)::BIGINT; END IF;
  RETURN amount;
END;
$$ LANGUAGE plpgsql STABLE;

-- Cuota mensual (sistema francés)
CREATE OR REPLACE FUNCTION monthly_payment(principal NUMERIC, annual_rate NUMERIC, years INT)
RETURNS NUMERIC AS $$
DECLARE
  r NUMERIC;
  n INT;
BEGIN
  r := annual_rate / 100 / 12;
  n := years * 12;
  IF r = 0 THEN RETURN principal / n; END IF;
  RETURN principal * r / (1 - POWER(1 + r, -n));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Cap rate de una propiedad
CREATE OR REPLACE FUNCTION calc_cap_rate(property_id BIGINT)
RETURNS NUMERIC AS $$
DECLARE
  p properties%ROWTYPE;
  annual_noi BIGINT;
  uf NUMERIC;
  value_clp BIGINT;
BEGIN
  SELECT * INTO p FROM properties WHERE id = property_id;
  SELECT value_clp INTO uf FROM fx_rates WHERE currency = 'UF' ORDER BY date DESC LIMIT 1;
  value_clp := (p.current_value_uf * uf)::BIGINT;
  annual_noi := COALESCE(p.monthly_rent_clp, 0) * 12 - COALESCE(p.monthly_expenses_clp, 0) * 12;
  IF value_clp = 0 THEN RETURN 0; END IF;
  RETURN ROUND(annual_noi::NUMERIC / value_clp * 100, 2);
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================
-- TRIGGERS (updated_at)
-- ============================================================
CREATE OR REPLACE FUNCTION trg_set_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_accounts_updated_at      BEFORE UPDATE ON accounts      FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
CREATE TRIGGER trg_transactions_updated_at  BEFORE UPDATE ON transactions  FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
CREATE TRIGGER trg_investments_updated_at   BEFORE UPDATE ON investments   FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
CREATE TRIGGER trg_properties_updated_at    BEFORE UPDATE ON properties    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
CREATE TRIGGER trg_businesses_updated_at    BEFORE UPDATE ON businesses    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- ============================================================
-- SEED CATEGORIES
-- ============================================================
INSERT INTO categories (name, type, is_system, color, icon) VALUES
  ('Salario',           'income',  true, '#34c77b', '💼'),
  ('Dividendos',        'income',  true, '#5b8def', '📈'),
  ('Arriendos',         'income',  true, '#a78bfa', '🏠'),
  ('Freelance',         'income',  true, '#2dd4bf', '💻'),
  ('Otros ingresos',    'income',  true, '#9aa0a6', '✨'),
  ('Supermercado',      'expense', true, '#34c77b', '🛒'),
  ('Restaurantes',      'expense', true, '#f97316', '🍽️'),
  ('Transporte',        'expense', true, '#5b8def', '🚗'),
  ('Suscripciones',     'expense', true, '#a78bfa', '📺'),
  ('Salud',             'expense', true, '#ef4444', '⚕️'),
  ('Educación',         'expense', true, '#facc15', '📚'),
  ('Gimnasio',          'expense', true, '#f472b6', '💪'),
  ('Servicios básicos', 'expense', true, '#9aa0a6', '💡'),
  ('Compras',           'expense', true, '#2dd4bf', '🛍️'),
  ('Viajes',            'expense', true, '#a78bfa', '✈️'),
  ('Hipoteca',          'expense', true, '#ef4444', '🏦'),
  ('Inversión',         'transfer',true, '#5b8def', '💎'),
  ('Sin categoría',     'expense', true, '#5a6068', '❓');

-- ============================================================
-- COMENTARIOS FINALES
-- ============================================================
-- Para refrescar materialized views:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_cashflow;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_category_spending;
--
-- mv_networth_history se popula via cron job que llama una función
-- snapshot_networth(date) que calcula todos los valores y hace INSERT.
