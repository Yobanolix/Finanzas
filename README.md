# Wealth OS v0.6

Sistema operativo patrimonial personal. PWA single-file, single-tenant. Todo en `localStorage` con respaldo JSON.

## Cambios v0.5 → v0.6

| Cambio | Detalle |
|---|---|
| **TC con ciclo** | Liabilities tipo `credit_card` ahora aceptan `creditLimit` (cupo) y `cutoffDay` (día de corte). Nuevo array `tcMovements[]` para registrar cargos durante el ciclo. |
| **Widget TC en Hoy** | Cards con barra de utilización + días al corte, solo si pasás el 30%. No llena el dashboard cuando no hace falta. |
| **Sección TC en Cashflow** | Por cada TC: cupo, días al corte, barra de utilización, lista de cargos del ciclo en curso, botón "+ Cargo" para registrar rápido. |
| **Progressive disclosure** | Forms de activos, deudas, metas y decisiones muestran 2-4 esenciales arriba. Resto en "Detalle avanzado" / "Supuestos del modelo" colapsado. |
| **Smart defaults por clase** | ETF → 7% retorno / liquidez 2d / riesgo alto. Caja → 0% / inmediata / low. Propiedad → 3% / locked / medio. Etc. Si dejás retorno o liquidez vacíos en un activo, se usa el default. |
| **Pie en cuotas (Modo A)** | Property templates con toggle "Pie en cuotas" + meses. Si on, el análisis se parte en Fase 1 (cuotas del pie) y Fase 2 (post-escrituración con hipoteca/arriendo). Cada fase muestra su impacto y veredicto por separado. |
| **Schema bump v5 → v6** | Migración no destructiva. Si venís de v0.5, tu data se preserva. TC tiene `creditLimit: null` + `cutoffDay: null` por default (no rompen nada hasta que los configurás). |

## Smoke test crítico

```bash
python -m http.server 5173
# abrir http://localhost:5173
```

**Migración (si venís de v0.5):**
1. Al abrir, esperás toast verde "Datos v05 migrados a v0.6".
2. Andá a Capital → Deudas. Si tenías una TC, debería seguir ahí. Click para abrirla. Ahora deberías ver dos campos nuevos: "Cupo TC" y "Día de corte" (sólo visibles si el tipo es `credit_card`).
3. Si no tenés TC todavía pero querés probar: + Deuda → Tipo: Tarjeta crédito → nombre = "TC Santander", saldo = 720000, cupo = 3000000, día corte = 5. Guardar.

**TC ciclo (la funcionalidad nueva):**
4. Andá a Cashflow. Scroll hasta abajo: deberías ver una sección "Tarjetas de crédito — ciclo en curso" con tu TC y una barra (probablemente verde si no cargaste movimientos).
5. Click "+ Cargo". Drawer abre con fecha de hoy, monto, concepto. Pone `monto 145000`, concepto "Test Jumbo". Guardar.
6. Drawer cierra. La barra de la TC debería subir. La cifra "Consumido este ciclo" debería estar en 145000 (o lo que cargaste).
7. Volvé a Hoy. Si pasás 30% del cupo, debería aparecer un panel "Tarjetas — ojo con esto" con la TC.
8. Click en un cargo para editarlo. Probá eliminar uno.

**Forms aligerados (lo que pediste):**
9. Capital → Activos → click + Activo. Sólo ves nombre + clase + moneda + valor visibles. Botón "Mostrar detalle avanzado ↓" abajo. Click → se despliega lo demás (retorno, liquidez, riesgo, etc.) en una sección punteada.
10. Sin tocar nada del avanzado, llená nombre="test ETF", clase=ETF, moneda=USD, valor=5000. Guardar. Andá a Capital — el ETF debería estar con liquidez "2d" y riesgo "Alto" automáticamente (defaults por clase).
11. Lo mismo con Deudas y Metas: 3-4 campos esenciales arriba, resto bajo "avanzado".

**Decisiones simplificadas:**
12. Decisiones → Comprar auto. El form ahora muestra sólo precio + pie. Botón "Mostrar supuestos del modelo ↓" abre el resto (tasa, plazo, mantención, reventa).
13. Cambiá sólo el pie a 3M. El veredicto debería recalcularse en vivo sin tocar nada más.

**Pie en cuotas:**
14. Decisiones → Comprar depto inversión. En "Supuestos del modelo" → tilda "Pie en cuotas". Ajustá "Cuotas del pie" a 30.
15. El análisis ahora muestra **dos paneles** lado a lado: "Fase 1 — Cuotas del pie" y "Fase 2 — Post escrituración". Cada uno tiene su veredicto.
16. La Fase 1 probablemente esté en "Esperar" o "Viable" según tus inputs (sólo cuota del pie sin arriendo). La Fase 2 con arriendo + hipoteca puede ser distinta.
17. Sacá el tilde de "Pie en cuotas". El análisis vuelve a un solo panel (modo tradicional v0.5).

**Respaldo + import:**
18. Topbar → Respaldo. JSON debe incluir `tcMovements`, y deudas TC con `creditLimit`/`cutoffDay`, y decisiones con `pieEnCuotas`/`cuotasMeses`.

## Atajos

`⌘K` / `Ctrl+K` paleta · `1-6` navegación · `Esc` cerrar drawer

## Estructura del repo

```
Finanzas/
├── backups/v0.2/     ← se mantiene
├── index.html        ← v0.6
├── manifest.json     ← v06
├── sw.js             ← cache v06
├── icon.svg
├── README.md         ← este archivo
├── ARCHITECTURE.md   ← se mantiene
└── schema.sql        ← se mantiene
```

## Lo que NO entra en v0.6 (postergado)

- **Modo B (motor multi-fase con proyección compuesta)** — la línea de patrimonio que muestra el "valle" durante cuotas y el alza después. Sale si Modo A se te queda corto.
- **Comparación lado-a-lado de decisiones guardadas.**
- **Gráficos de proyección** en el drawer.
- **Negocios** con progressive disclosure (lo dejamos para más adelante porque no fue queja tuya).
- **Reportes / cierre de mes.**

## Stack

HTML + CSS + JS vanilla. ~164KB. localStorage. Service worker para offline.

## Privacidad

Todo vive en `localStorage`. Hacé respaldo regular.
