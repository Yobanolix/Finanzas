# Wealth OS — Architecture Document

**Versión:** 1.0
**Owner:** Giovanni
**Modelo de deployment:** Single-tenant (un solo usuario)
**Status:** Design doc para v2 (post-MVP). v1 ya está en `index.html`.

---

## 1. Resumen ejecutivo

Wealth OS es un sistema operativo personal para gestión patrimonial activa: cuentas, inversiones, inmobiliario, negocios, simulador estratégico y un análisis IA contextual. No es una app de control de gastos. El usuario objetivo (vos) es un perfil agresivo con horizonte multi-asset, capacidad de inversión recurrente y preferencia por automatización vs. reporting manual.

**Decisión fundacional:** single-tenant. No vamos a multi-tenancy ni auth multi-usuario hasta que haya razón comercial. Esto nos ahorra ~40% de la complejidad operativa de la app, permite un esquema de DB mucho más limpio (sin `user_id` por todos lados, sin row-level security), y elimina la necesidad de un onboarding/billing/admin layer. Si más adelante hay decisión de comercializar, se rearma la capa de auth y se migra el schema con un `user_id` en cada tabla — costo estimado de esa migración: 1 sprint.

**Estrategia v1 → v2:**
- **v1** (lo que ya está): PWA estática single-file, localStorage, todo manual. Sirve como playground para validar UX y modelo de datos antes de invertir en infra. Deployable a GitHub Pages en 5 minutos.
- **v2**: Backend Next.js + Postgres + Fintoc + Claude API. La PWA pasa a ser un thin client que pega contra `/api/*`. Migración de datos: export JSON de v1 → seed script en v2.

---

## 2. Decisiones arquitectónicas críticas (ADRs)

### ADR-001: Single-tenant > multi-tenant

**Decisión:** sin auth multi-usuario, sin `user_id` en el schema, una sola base de datos para un único humano.

**Tradeoff:** se pierde la opción de "ofrecerla a un amigo" sin reescribir. Se gana ~3-4 semanas de tiempo de desarrollo y simplificación operacional importante (sin Clerk/Auth0/Supabase Auth, sin RLS, sin sistema de invitaciones).

**Mitigación:** la app igualmente se expone con HTTP Basic Auth o un middleware con un token único en la cookie, para evitar acceso casual si alguien encuentra la URL. No es "seguridad" sino "no me espíen el patrimonio".

### ADR-002: PWA (no nativa)

**Decisión:** la UI vive en una PWA instalable, no en apps nativas iOS/Android.

**Tradeoff:** no hay biometría nativa por defecto (se puede agregar con WebAuthn), no hay widgets en home screen iOS, push notifications limitadas en iOS Safari. Se gana: un solo codebase, deploy a Vercel/GitHub Pages, no App Store, no fees de Apple/Google, iteración 10x más rápida.

**Mitigación:** WebAuthn para login biométrico en clientes que lo soportan (Chrome Android, Safari iOS 16.4+).

### ADR-003: Fintoc como única fuente de truth bancaria

**Decisión:** integramos Fintoc para sincronización de cuentas y movimientos. No usamos scraping, no usamos OFX, no usamos múltiples agregadores.

**Tradeoff:** dependencia de un solo proveedor; si Fintoc cambia pricing o pierde un banco, dolor. Costo recurrente (CLP 200-500 por cuenta/mes según plan).

**Mitigación:** el modelo de datos no tiene acoplamiento fuerte con Fintoc — los `transactions` son nuestras, no de Fintoc. Si hay que migrar a Belvo o un agregador propio, el cambio es un nuevo adapter en la capa de ingestion. Datos ya ingresados se mantienen.

### ADR-004: Categorización híbrida (reglas + Claude)

**Decisión:** capa 1 reglas determinísticas (regex sobre descripción), capa 2 fallback a Claude para movimientos no categorizables.

**Tradeoff:** una capa puramente ML local (XGBoost o similar) sería más barato a escala y privacidad total. Una capa puramente Claude sería más simple pero costosa por movimiento.

**Mitigación:** ~85% de los movimientos en Chile son recurrentes y caen en reglas (supermercado, suscripciones, salario). El 15% restante se manda a Claude en batches de 50 con prompt estructurado y tool use → ~CLP 30 mensuales en API.

### ADR-005: Postgres como única base de datos

**Decisión:** Postgres (Supabase o Neon). No Mongo, no DynamoDB, no separar transactional de analytical.

**Tradeoff:** Postgres requiere pensar en migraciones desde el día 1. A favor: SQL es la herramienta correcta para data financiera relacional, queries analíticas via window functions, time-series con TimescaleDB extension si se necesita, y el rol/perfil del owner (analista BI con SQL) hace que sea casi parte del producto poder hacer queries directas a la DB para análisis ad-hoc.

### ADR-006: Server-side rendering primero, sin client-side state framework pesado

**Decisión:** Next.js App Router con React Server Components para data fetching. Sin Redux/Zustand global. Estado local con React Query para mutations y caching.

**Tradeoff:** RSC tiene una curva de aprendizaje. Vale la pena porque elimina la mayor fuente de bugs en dashboards financieros: estado desincronizado entre cliente y servidor.

### ADR-007: Cero observabilidad propia en v2

**Decisión:** logging básico con `console.log` capturado por Vercel + Sentry free tier para errores. Sin DataDog, sin OpenTelemetry, sin métricas custom.

**Tradeoff:** observabilidad pobre. Aceptable: un solo usuario, traffic bajísimo, los problemas se ven en uso. Si la app empieza a fallar silenciosamente, se agrega después.

---

## 3. Stack tecnológico

### 3.1 Frontend

| Layer | Tecnología | Razón |
|---|---|---|
| Framework | **Next.js 14 (App Router)** | RSC para data fetching directo desde DB, edge runtime, ecosistema, deploy en Vercel one-click |
| Lenguaje | **TypeScript estricto** | No negociable en fintech. `strict: true`, `noUncheckedIndexedAccess: true` |
| Estilos | **Tailwind CSS + CSS variables** | Velocidad de iteración + theming consistente. El v1 ya tiene la paleta |
| Componentes | **shadcn/ui** (copy-paste, no NPM) | Control total del código, sin lock-in, Radix accessibility por debajo |
| Charts | **Recharts** o **Visx** | Recharts para 80% de los casos, Visx cuando se necesite control fino (heatmaps, sankey) |
| Tablas | **TanStack Table v8** | Sort, filter, pagination headless. Crítico para `/transactions` con miles de filas |
| Forms | **React Hook Form + Zod** | Validación shared con backend, type-safe |
| Date math | **date-fns** (no Moment) | Tree-shakeable, immutable, suficiente |
| Money math | **dinero.js v2** | Aritmética monetaria sin floating point bugs. Crítico |
| PWA | Next.js `manifest.json` + custom SW | Service worker manual para control fino de cache |

### 3.2 Backend

| Layer | Tecnología | Razón |
|---|---|---|
| Runtime | **Node.js 20 LTS** en Vercel | Edge runtime para endpoints rápidos, Node runtime para Fintoc/Claude |
| API | **Next.js Route Handlers** | Mismo deploy que frontend, simplicidad |
| ORM | **Drizzle ORM** | Migraciones declarativas, SQL real, mejor DX que Prisma en TypeScript, sin runtime overhead |
| Validación | **Zod** | Compartido con frontend |
| Auth | **HTTP Basic Auth + middleware** | Suficiente para single-tenant. Token en cookie httpOnly secure |
| Background jobs | **Vercel Cron + QStash** | Cron para syncs diarios de Fintoc, QStash para tareas más largas (análisis IA mensual) |
| Email | **Resend** | Para alertas críticas (movimiento sospechoso, sync falló) |
| Secrets | **Vercel Environment Variables** + **Doppler** (opcional) | API keys de Fintoc, Anthropic, etc |

### 3.3 Base de datos

| Layer | Tecnología | Razón |
|---|---|---|
| Database | **Postgres 16** | Estándar |
| Hosting | **Neon** (serverless) o **Supabase** | Neon: branching y serverless ideal para hobby; Supabase: si querés auth + storage incluidos. Yo iría Neon para single-tenant |
| Extension | **pg_partman** + **TimescaleDB** (opcional) | Solo si las transacciones llegan a millones. No en v2 inicial |
| Backup | Neon point-in-time recovery (incluido) | Suficiente |

### 3.4 Integraciones

| Servicio | Para qué | Costo aproximado |
|---|---|---|
| **Fintoc** | Sync de cuentas bancarias y movimientos | CLP 200-500/cuenta/mes según plan |
| **Anthropic API (Claude Sonnet 4.6)** | Categorización de fallback + análisis mensual + simulador conversacional | USD 5-15/mes a tu volumen |
| **Resend** | Emails transaccionales | Free tier (100 emails/día) |
| **Sentry** | Error tracking | Free tier |
| **Vercel** | Hosting | Free hobby tier o Pro USD 20/mes |
| **Neon** | Postgres | Free tier suficiente; USD 19/mes si crece |
| **Upstash QStash** | Background jobs | Free tier |

**Costo total operativo estimado v2:** USD 30-50/mes total. CLP ~25.000-45.000.

### 3.5 Lo que NO usamos (y por qué)

- ❌ **GraphQL**: REST simple es suficiente, no hay clientes externos.
- ❌ **Kubernetes / Docker**: Vercel maneja el deployment.
- ❌ **Redis**: Postgres puede hacer caching con `pg_trgm` + materialized views. Redis sería overkill.
- ❌ **Microservicios**: monolito Next.js con módulos bien aislados. Microservicios para single-tenant es overengineering criminal.
- ❌ **Kafka / RabbitMQ**: QStash o Postgres LISTEN/NOTIFY son suficientes.
- ❌ **MongoDB**: la data es relacional.
- ❌ **tRPC**: REST + Zod es suficiente y más legible.

---

## 4. Modelo de datos

### 4.1 Visión general

Tablas core: `accounts`, `transactions`, `categories`, `investments`, `dividends`, `properties`, `mortgages`, `businesses`, `business_movements`, `scenarios`, `ai_analyses`, `fx_rates`.

Vistas materializadas para métricas costosas: `mv_monthly_cashflow`, `mv_networth_history`, `mv_category_spending`.

### 4.2 Diagrama relacional

```
                  ┌────────────────┐
                  │   fx_rates     │  (snapshot diario UF/USD)
                  └────────────────┘

  ┌─────────────┐      ┌─────────────────┐      ┌───────────────┐
  │  accounts   │──1:N─│  transactions   │─N:1──│   categories  │
  └─────────────┘      └─────────────────┘      └───────────────┘
                              │
                              │ raw_data (Fintoc payload)
                              ▼
                       ┌──────────────────┐
                       │ fintoc_sync_log  │
                       └──────────────────┘

  ┌────────────┐  ┌──────────┐  ┌────────────┐  ┌────────────────────┐
  │investments │──│dividends │  │ properties │──│     mortgages      │
  └────────────┘  └──────────┘  └────────────┘  └────────────────────┘
                                       │
                                       └──────property_movements (gastos/arriendo)

  ┌────────────┐  ┌───────────────────────┐
  │ businesses │──│  business_movements   │
  └────────────┘  └───────────────────────┘

  ┌──────────────────┐
  │   scenarios      │  (simulaciones guardadas)
  └──────────────────┘

  ┌──────────────────┐
  │   ai_analyses    │  (output de Claude, con prompt + response)
  └──────────────────┘
```

### 4.3 Decisiones de modelado

**Money como BIGINT en centavos**, no DECIMAL ni FLOAT. Todos los montos se guardan en la unidad mínima (CLP entero, USD centavos, UF micro-UF con 4 decimales). Esto elimina bugs de floating point en agregaciones. La conversión a display es responsabilidad del frontend usando `dinero.js`.

**Soft delete por defecto** con `deleted_at TIMESTAMPTZ`. Auditable, undoable. Las queries usan vistas o filtros con `deleted_at IS NULL`.

**Timestamps en TIMESTAMPTZ** (con timezone). Aplicación corre en `America/Santiago` pero almacenamos en UTC.

**Currencies como ENUM** (`CLP`, `USD`, `UF`, `EUR`). Restringido por design — no queremos categorías de moneda libres.

**Categories como tree** con `parent_id` self-FK. Permite "Restaurantes" como subcategoría de "Comida". Limit recursion a 3 niveles vía app logic.

**Fintoc payload completo en JSONB** en cada transacción, no solo los campos parseados. Si un día queremos un campo que no parseamos hoy, está ahí.

**Snapshots de patrimonio** en `mv_networth_history` recalculados nightly. No reconstruimos patrimonio sumando transacciones desde el inicio cada vez — es O(n) en transacciones.

Ver `schema.sql` para el DDL completo y ejecutable.

---

## 5. Estructura de carpetas (Next.js)

```
wealth-os/
├── app/                         # Next.js App Router
│   ├── layout.tsx
│   ├── page.tsx                 # Dashboard
│   ├── accounts/
│   │   ├── page.tsx
│   │   └── [id]/page.tsx
│   ├── transactions/
│   │   ├── page.tsx
│   │   └── components/
│   ├── investments/
│   │   ├── page.tsx
│   │   ├── [id]/page.tsx
│   │   └── compound/page.tsx
│   ├── real-estate/
│   │   ├── page.tsx
│   │   └── [id]/page.tsx
│   ├── businesses/
│   │   └── page.tsx
│   ├── simulator/
│   │   ├── auto/page.tsx
│   │   ├── property/page.tsx
│   │   ├── savings/page.tsx
│   │   └── business/page.tsx
│   ├── ai/
│   │   └── page.tsx
│   └── api/
│       ├── fintoc/
│       │   ├── webhook/route.ts        # Recibe eventos de Fintoc
│       │   ├── connect/route.ts        # OAuth flow
│       │   └── sync/route.ts           # Sync manual
│       ├── ai/
│       │   ├── analyze/route.ts        # Análisis mensual
│       │   ├── categorize/route.ts     # Categorización bulk
│       │   └── chat/route.ts           # Simulador conversacional
│       ├── transactions/route.ts
│       ├── investments/route.ts
│       ├── properties/route.ts
│       ├── businesses/route.ts
│       ├── scenarios/route.ts
│       ├── export/route.ts             # JSON export
│       ├── import/route.ts             # JSON import
│       └── cron/
│           ├── daily-sync/route.ts     # Pull Fintoc daily
│           ├── monthly-snapshot/route.ts
│           └── fx-rates/route.ts       # Scrap UF/USD
│
├── components/
│   ├── ui/                      # shadcn/ui primitives
│   ├── charts/
│   │   ├── networth-chart.tsx
│   │   ├── allocation-donut.tsx
│   │   ├── cashflow-bars.tsx
│   │   └── compound-line.tsx
│   ├── dashboard/
│   │   ├── hero-metrics.tsx
│   │   ├── top-categories.tsx
│   │   └── recent-activity.tsx
│   ├── transactions/
│   │   ├── transactions-table.tsx
│   │   ├── transaction-form.tsx
│   │   └── category-picker.tsx
│   ├── simulator/
│   │   ├── property-sim.tsx
│   │   ├── auto-sim.tsx
│   │   └── savings-sim.tsx
│   ├── shell/
│   │   ├── sidebar.tsx
│   │   ├── header.tsx
│   │   └── bottom-nav.tsx
│   └── ai/
│       ├── analysis-card.tsx
│       └── chat-thread.tsx
│
├── lib/
│   ├── db/
│   │   ├── client.ts            # Drizzle instance
│   │   ├── schema.ts            # Schema declarativo
│   │   └── migrations/          # Auto-generadas
│   ├── fintoc/
│   │   ├── client.ts            # SDK wrapper
│   │   ├── sync.ts              # Sync logic
│   │   ├── webhook-handler.ts
│   │   └── types.ts
│   ├── ai/
│   │   ├── claude.ts            # Anthropic SDK client
│   │   ├── categorizer.ts       # Reglas + fallback
│   │   ├── analyzer.ts          # Análisis mensual
│   │   ├── prompts.ts           # System prompts y tool defs
│   │   └── tools.ts             # Tool use definitions
│   ├── finance/
│   │   ├── networth.ts          # calcNetWorth, calcAssets, calcLiabilities
│   │   ├── cashflow.ts          # savingsRate, burnRate, runway
│   │   ├── mortgage.ts          # amortization, remaining principal
│   │   ├── investment.ts        # compound, IRR, weighted return
│   │   ├── real-estate.ts       # capRate, cashOnCash, ROI
│   │   ├── currency.ts          # UF, USD conversion
│   │   └── simulators.ts        # auto, property, savings, business
│   ├── auth/
│   │   ├── basic-auth.ts
│   │   └── middleware.ts
│   ├── utils/
│   │   ├── format.ts            # fmtCLP, fmtUF, fmtPct
│   │   ├── date.ts
│   │   └── csv.ts               # parseCSV, generateCSV
│   └── env.ts                   # Zod-validated env vars
│
├── middleware.ts                # Basic auth + rate limit
├── drizzle.config.ts
├── next.config.mjs
├── tailwind.config.ts
├── tsconfig.json                # strict: true
├── package.json
├── .env.example
├── README.md
└── ARCHITECTURE.md
```

---

## 6. Roadmap

### Fase 0 — v1 PWA (✅ HECHO)
- HTML/CSS/JS single file
- 7 secciones funcionales
- Datos demo + manual + CSV import
- localStorage + backup JSON
- Cálculos: UF/CLP/USD, ROI, cap rate, compound, savings rate, runway, leverage
- Simuladores: auto, depto, ahorro, negocio
- Deployable a GitHub Pages

### Fase 1 — Infra base (2 semanas)
- Next.js + Tailwind + shadcn/ui scaffold
- Drizzle schema + primera migración
- Neon Postgres setup
- Basic auth middleware
- Migrar export JSON de v1 → seed inicial
- Dashboard + Accounts + Transactions con DB real
- Deploy en Vercel

### Fase 2 — Fintoc (2 semanas)
- Fintoc onboarding (link credenciales, OAuth)
- Webhook receiver con HMAC verification
- Sync diario via Vercel Cron
- Categorización por reglas (Capa 1)
- UI para conectar/desconectar cuentas
- Conciliación: detectar duplicados con CSV imports previos

### Fase 3 — Inversiones + inmobiliario reales (1.5 semanas)
- Migrar módulos de v1 al backend
- Integrar API de precios para refrescar `current_price` de inversiones (Alpha Vantage free tier o yfinance via Python serverless function)
- Cron diario de FX rates (UF desde sii.cl scraping con respeto, USD desde BCRA o Banco Central)
- Recalcular `mv_networth_history` cada noche

### Fase 4 — Claude integration (1 semana)
- `lib/ai/categorizer.ts` con fallback a Claude
- `/api/ai/analyze` con tool use estructurado
- Cron mensual: análisis automático del mes cerrado
- UI Análisis IA conectada a outputs reales
- Chat conversacional para simulador (`/api/ai/chat` con history)

### Fase 5 — Polish + extras (1 semana)
- WebAuthn para login biométrico
- Notificaciones push (movimientos > X CLP, alertas IA)
- Export contable: PDF resumen mensual
- Backup automático a S3 (R2 Cloudflare free tier)
- Dark/light mode toggle

**Total estimado:** 7-8 semanas a dedicación part-time (10-15 hrs/semana). Si lo hacés full focus, 4 semanas.

---

## 7. Integración Fintoc — flujo realista

### 7.1 Onboarding

1. Te creás cuenta en Fintoc.com como **empresa**. Fintoc no atiende personas naturales. Si no tenés persona jurídica, los caminos son:
   - **Sociedad ya existente** (si tenés EIRL o similar)
   - **Onboarding como dev sandbox** (gratis, limitado a tu propia data; algunas funciones requieren plan pago)
   - **Persona natural via algún plan especial** — preguntar a Fintoc soporte; algunos casos los aprueban
2. Una vez aprobado, te dan `FINTOC_API_KEY_PUBLIC` y `FINTOC_API_KEY_SECRET`.
3. Configurás webhook endpoint: `https://wealth-os.vercel.app/api/fintoc/webhook` con secreto para HMAC.

### 7.2 Vinculación de cuenta (Link)

```
┌──────┐     ┌─────────────┐     ┌──────────┐
│ User │──1──│ /api/fintoc │──2──│  Fintoc  │
└──────┘     │  /connect   │     │  Widget  │
             └─────────────┘     └──────────┘
                                       │
                                  3. user enters
                                  banking creds
                                       │
                                       ▼
                                  4. Fintoc returns
                                  link_token
                                       │
                              ┌────────┴────────┐
                              │                 │
                              ▼                 ▼
                       ┌──────────────┐  ┌──────────────┐
                       │/api/fintoc/  │  │ stores in    │
                       │  webhook     │  │ accounts.    │
                       │              │  │fintoc_link_id│
                       └──────────────┘  └──────────────┘
```

### 7.3 Sync diario (Vercel Cron)

```typescript
// app/api/cron/daily-sync/route.ts
export async function GET() {
  const accounts = await db.select().from(accountsTable).where(...);
  for (const acc of accounts) {
    if (!acc.fintoc_link_id) continue;
    const movements = await fintoc.movements.list({
      link_token: acc.fintoc_link_id,
      since: acc.last_synced_at,
    });
    for (const m of movements) {
      await upsertTransaction(acc.id, m);
    }
    await db.update(accountsTable)
      .set({ last_synced_at: new Date() })
      .where(eq(accountsTable.id, acc.id));
  }
  // Trigger categorización
  await fetch(`${SITE_URL}/api/ai/categorize`, { method: 'POST' });
}
```

### 7.4 Categorización

```typescript
// lib/ai/categorizer.ts
const RULES = [
  { pattern: /jumbo|lider|tottus|santa isabel|unimarc/i, category: 'Supermercado' },
  { pattern: /uber|cabify|didi/i,                        category: 'Transporte' },
  { pattern: /netflix|spotify|hbo|disney/i,              category: 'Suscripciones' },
  { pattern: /gym|smart fit/i,                           category: 'Gimnasio' },
  // ~50 reglas más
];

export async function categorize(tx: Transaction) {
  for (const rule of RULES) {
    if (rule.pattern.test(tx.description)) return rule.category;
  }
  return null; // Fallback a Claude
}

export async function categorizeBatch(uncategorized: Transaction[]) {
  // Solo si hay >= 10 uncategorized para amortizar costo
  if (uncategorized.length < 10) return;
  const result = await claude.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 4000,
    system: CATEGORIZER_SYSTEM_PROMPT,
    messages: [{ role: 'user', content: JSON.stringify(uncategorized) }],
    tools: [{ name: 'set_categories', input_schema: SET_CATS_SCHEMA }],
    tool_choice: { type: 'tool', name: 'set_categories' },
  });
  // Parse tool_use, update DB
}
```

### 7.5 Conciliación con imports previos

Si ya importaste cartolas en CSV antes de conectar Fintoc, va a haber duplicados. Estrategia:
- Hash determinístico de cada movimiento: `sha256(date + amount + description.normalized)`.
- Cuando llega un movimiento Fintoc, calculá su hash y buscá colisión con últimos 60 días.
- Si match, descartar (preferir fuente Fintoc por ser canónica).

---

## 8. Integración Claude — patrones

### 8.1 Análisis mensual automático

**Trigger:** cron primer día del mes.

**Input:** snapshot agregado del mes anterior — métricas calculadas en DB, top categorías, deltas vs promedio últimos 6 meses.

**System prompt:** asesor financiero personal con contexto chileno, perfil agresivo, edad 26, conocimiento BI. Output estructurado vía tool use.

**Tool schema:**

```typescript
const ANALYSIS_TOOL = {
  name: 'submit_monthly_analysis',
  description: 'Submit structured monthly financial analysis',
  input_schema: {
    type: 'object',
    properties: {
      summary: { type: 'string', description: 'Executive summary 2-3 sentences' },
      key_metrics_delta: {
        type: 'object',
        properties: {
          networth_change_pct: { type: 'number' },
          savings_rate: { type: 'number' },
          notable_outlier: { type: 'string' },
        },
      },
      recommendations: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            icon: { type: 'string' },
            title: { type: 'string' },
            rationale: { type: 'string' },
            estimated_impact_clp: { type: 'number' },
            priority: { enum: ['high','medium','low'] },
          },
        },
      },
      alerts: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            severity: { enum: ['critical','warning','info'] },
            title: { type: 'string' },
            description: { type: 'string' },
            recommended_action: { type: 'string' },
          },
        },
      },
    },
    required: ['summary','recommendations','alerts'],
  },
};
```

Costo: ~3000 input tokens + ~1500 output tokens por análisis = USD 0.04. Mensual: USD 0.04. Anual: USD 0.50. Despreciable.

### 8.2 Categorización (ver 7.4)

Costo: depende de volumen. Para ~50 transacciones uncategorized/mes: USD 0.10/mes.

### 8.3 Simulador conversacional

Endpoint `/api/ai/chat` con historial mantenido en `ai_analyses` (tipo `chat`). System prompt incluye snapshot del patrimonio actual. Permite preguntas como "si compro un depto de 4000 UF con 25% de pie, ¿qué pasa con mi cash flow?". Claude llama internamente a `simulator.property` (tool use) y devuelve respuesta narrada con números.

Costo: ~USD 0.02 por turn. 50 turns/mes: USD 1.

### 8.4 Total Claude

Estimado: **USD 3-8/mes** a uso intenso.

---

## 9. Seguridad

### 9.1 Capas

| Capa | Control |
|---|---|
| **Red** | Vercel automático: HTTPS only, HSTS, TLS 1.3 |
| **Auth** | HTTP Basic Auth + middleware → cookie httpOnly secure samesite=strict con JWT firmado |
| **Auth biométrica** (v3) | WebAuthn opcional para clientes que lo soportan |
| **Secrets** | Vercel env vars con scoping production/preview; rotación trimestral |
| **DB** | Neon con conexión vía connection pooler, SSL forzado, IP allowlist a Vercel egress |
| **Encryption at rest** | Neon lo da por default (AES-256). Adicionalmente, `fintoc_link_id` y datos sensibles encriptados con `pgcrypto` y key en env |
| **Encryption in transit** | TLS everywhere |
| **CSRF** | Next.js middleware con Origin check |
| **Rate limit** | Upstash rate limiter en `/api/*`. 100 req/min por IP |
| **Webhook integrity** | HMAC SHA-256 con secret en cada webhook Fintoc |
| **Logs** | Nada de PII en logs. Montos enteros sí; descripciones de transacciones tokenizadas |
| **Backups** | Neon PITR + export semanal a R2 Cloudflare (encrypted) |
| **Auditing** | Tabla `audit_log` con cada mutation (who/what/when), append-only |

### 9.2 Threat model

| Threat | Mitigación |
|---|---|
| Acceso casual a URL pública | Basic Auth bloquea |
| Credentials leaked | Rotación + monitoreo Sentry para 401 spikes |
| Webhook spoof | HMAC verification |
| SQL injection | Drizzle parametriza queries |
| XSS | React escapa por default, CSP estricta en `next.config.mjs` |
| Dependencia compromise | Renovate bot + `npm audit` en CI |
| Pérdida de datos | Backups Neon + R2 + posibilidad de re-sync desde Fintoc |
| Comprometimiento de la cuenta Fintoc | Read-only scope; aún si comprometen, no pueden hacer transferencias |

### 9.3 Lo que NO hacemos en v2 (por ser overkill para single-tenant)

- ❌ SOC 2
- ❌ Penetration testing formal
- ❌ Bug bounty
- ❌ MFA propio (basic auth + biometric WebAuthn es suficiente)
- ❌ SIEM
- ❌ DDoS protection custom (Vercel da algo por default)

Si la app se comercializa, esto sube en prioridad.

---

## 10. Escalabilidad

### 10.1 Cuellos de botella esperados

| Escenario | Cuello | Solución |
|---|---|---|
| 100k transacciones en DB | Queries de dashboard lentos | Indices + materialized views + pre-agregación |
| Sync de 5 cuentas en paralelo | Rate limit Fintoc | Queue con QStash, sync secuencial |
| Charts con 10 años de data | Bundle de Chart.js + payload | Decimation client-side + lazy loading |
| Análisis Claude > 30s | Vercel timeout | Mover a Vercel Edge Functions o background job con notificación push |

### 10.2 Patrones

**Pre-agregación.** No calculamos métricas on-demand desde transacciones cuando hay > 10k filas. Las vistas materializadas se refrescan en cron nocturno:

```sql
CREATE MATERIALIZED VIEW mv_monthly_cashflow AS
  SELECT date_trunc('month', date) AS month,
         SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS income,
         SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS expenses
  FROM transactions
  WHERE deleted_at IS NULL
  GROUP BY date_trunc('month', date);

REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_cashflow;
```

**Pagination cursor-based**, no offset. `WHERE date < $cursor ORDER BY date DESC LIMIT 50`.

**Edge caching** en endpoints read-only que no dependen del usuario directamente (ej: FX rates).

### 10.3 Si esto se vuelve SaaS

Cambios mínimos necesarios:
1. Agregar `user_id` (UUID) en cada tabla, FK a `users`.
2. Habilitar Row-Level Security en Postgres.
3. Auth real con Clerk o Supabase Auth.
4. Stripe para billing.
5. Onboarding flow + invitaciones.

Estimación: 2-3 semanas + costo legal/compliance que es real (KYC, GDPR, ley 19.628 Chile).

---

## 11. Costos consolidados

### 11.1 Mensual (v2 single-tenant)

| Servicio | Costo |
|---|---|
| Vercel Hobby | USD 0 (suficiente) o Pro USD 20 si querés analytics + larger functions |
| Neon Postgres | USD 0 free tier o USD 19 Launch |
| Fintoc | CLP 500/cuenta × 5 cuentas = CLP 2.500 ≈ USD 3 |
| Anthropic API | USD 5-15 según uso |
| Resend | USD 0 |
| Sentry | USD 0 |
| Dominio (opcional) | USD 12/año |
| **Total mínimo** | **USD 8-18/mes** |
| **Total cómodo** | **USD 35-55/mes** |

### 11.2 Tiempo de desarrollo

| Fase | Tiempo realista |
|---|---|
| Setup + auth + DB + UI base | 2 semanas |
| Fintoc integration | 1.5 semanas |
| Categorización + Claude | 1 semana |
| Inversiones + inmobiliario | 1.5 semanas |
| Simulador + IA conversacional | 1 semana |
| Polish + deploy | 0.5 semanas |
| **Total** | **7-8 semanas part-time** |

---

## 12. Decisiones que postergamos explícitamente

- **Multi-currency conversion en tiempo real**: para v2 usamos snapshot diario, no en vivo. Aceptable a tu volumen.
- **Tax module**: declaración renta automática. Útil pero complejo (operación renta SII). Después.
- **Mobile app nativa**: no antes de validar uso intensivo en PWA por 6+ meses.
- **Compartir reportes con asesor**: feature de export PDF, después de v2.
- **Crypto integration (CoinGecko/Binance)**: si lo necesitás, agregamos un adapter más. Por ahora se ingresan como `investment.type = 'crypto'` con precio manual.
- **Algorithmic trading / DCA automation**: ámbito fuera de este producto.

---

## 13. Crítica honesta al diseño

Como buen design doc, lo que NO está perfecto:

1. **Single point of failure en Fintoc.** Si Fintoc cae 48hs, no podés sincronizar. Mitigación parcial: CSV import sigue funcionando.
2. **Claude como dependencia para categorización es ineficiente** a escala — si llegás a 5k transacciones/mes, el costo y latencia justifican entrenar un clasificador local (BERT pequeño fine-tuned con tus propias categorizaciones). No es prioridad ahora.
3. **No hay versioning de cálculos.** Si en 6 meses cambiás cómo calculás "savings rate" (ej: incluir aportes inversores), los gráficos históricos cambian retroactivamente. Solución: guardar `metric_definition_version` en `mv_networth_history`. Lo dejamos para v3.
4. **Backup a R2 no está automatizado en MVP**. Riesgo bajo (Neon ya tiene PITR) pero recomendado agregar como cron semanal.
5. **PWA no garantiza offline real para escrituras**. Si estás sin internet, el cliente cachea reads pero las mutations fallan. Si querés offline write, hay que agregar IndexedDB queue + sync con background. Costo: 1 semana de trabajo. No vale la pena al principio.
6. **El Fintoc-onboarding es la mayor fricción de v2**. Si tu sociedad no califica, hay que evaluar alternativas: Belvo, scraping legal, o mantenerse en CSV. Esto debería testearse en semana 1, no semana 5.

---

## 14. Next steps inmediatos

1. **Probar v1 en producción** una semana (deployar a GitHub Pages, usar diariamente, anotar fricciones reales).
2. **Validar Fintoc onboarding** (no avanzar con el resto hasta saber que podés conectar tus cuentas).
3. **Setup repo en GitHub** con la estructura de carpetas de §5.
4. **Migrar el schema de v1 → `schema.sql`** y correr `drizzle-kit push` contra Neon.
5. **Migrar Dashboard al backend** como primera ruta funcional (la que más usás).

El resto del roadmap se va destrabando una vez que estos 5 puntos estén OK.

---

*Fin del documento. Si algo no quedó claro o querés que profundice en alguna sección (ej: prompt engineering de Claude, manejo fino de UF para inmobiliario, o pattern matching para categorización chilena), pedímelo.*
