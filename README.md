# Wealth OS v0.5

Sistema operativo patrimonial personal. PWA single-file, single-tenant. Todo en `localStorage` con respaldo JSON.

## ¿Qué cambió de v0.4 a v0.5?

**Decision Lab profundo (Slice 3)** — la sección Decisiones pasa de placeholder a herramienta operativa real:

| Cambio | Detalle |
|---|---|
| **8 plantillas reales** | Auto, vivienda principal, depto inversión, emprender, aumentar inversión, prepagar deuda, tomar crédito, cambiar trabajo |
| **Cada plantilla calcula** | Caja inicial, Δ flujo libre, liquidez post, runway post, DTI post, deuda agregada, patrimonio proyectado a 12/24/36m |
| **Impacto en cada meta** | Por cada goal activo: "adelanta X meses" / "retrasa Y meses" / "ahora alcanzable" / "se vuelve inalcanzable" |
| **Veredicto multi-criterio** | Viable / Esperar / No ahora, con razones específicas y condiciones bajo las cuales sí conviene |
| **Decisiones persistentes** | Cada decisión se guarda con nombre + notas, podés volver a editarla, ver el veredicto actualizado, eliminarla |
| **Live update** | Cambiás un input y todo se recalcula al instante: cuota, runway, veredicto, impacto en metas |
| **Polish español** | Today → Hoy, Decision Lab → Decisiones, Venture Lab → Negocios, Backup → Respaldo, Rates → Tipos |
| **Schema v4 → v5** | Migración automática que solo agrega `decisions: []`. Tu data v0.4 se preserva |

## Las 8 plantillas — qué calcula cada una

**🚗 Comprar auto** — precio, pie, tasa, plazo, mantención, valor de reventa estimado. Devuelve cuota, intereses totales, TCO, depreciación 12m.

**🏠 Comprar vivienda principal** — UF, pie %, tasa, plazo, gastos comunes, plusvalía. Devuelve dividendo mensual CLP, costos de compra, plusvalía esperada.

**🏢 Comprar depto inversión** — todo lo anterior + arriendo, vacancia. Devuelve cap rate, cash-on-cash, NOI anual, cash flow neto mensual.

**◆ Emprender** — capital, burn pre-breakeven, meses a BE, utilidad post, tu participación, probabilidad de éxito, múltiplo. Devuelve payback, valor estimado, valor esperado ponderado por probabilidad.

**↗ Aumentar inversión mensual** — aporte extra, retorno anual, horizonte. Devuelve capital final, ganancia esperada, múltiplo. Nota: el aporte sale del flujo libre pero queda invertido.

**↘ Prepagar deuda** — monto a prepagar, tasa, años restantes, cuota actual, % reducción. Devuelve intereses ahorrados, flujo libre liberado, recuperación de la inversión.

**↪ Tomar crédito** — monto, tasa, plazo, propósito (inversión / consumo / refinanciar). Devuelve cuota, total a pagar, intereses, y nota crítica según propósito.

**↻ Cambiar trabajo / renunciar** — sueldo nuevo, actual, meses de gap, costos extra durante gap. Devuelve diferencial mensual, pérdida en gap, acumulado neto a horizonte, breakeven en meses.

## Veredicto — cómo se decide

**Criterios críticos (No ahora):**
- Cash post-decisión < 0
- Flujo libre post < 0
- DTI post > 40%

**Criterios warning (Esperar / mejorar):**
- Liquidez post bajo medio colchón (3m de burn)
- Runway post < 3 meses
- DTI post entre 30% y 40%
- Flujo libre cae más de 70%

**Si todo verde:** Viable.

Cada warning/crítico viene con una **condición específica** para que se vuelva viable. Ejemplo: "Conseguir $4M más en cash rápido" o "Reducir gastos en $300K/mes".

## Atajos de teclado

| Atajo | Acción |
|---|---|
| `⌘K` / `Ctrl+K` | Paleta de comandos |
| `1`–`6` | Navegar entre módulos (Hoy, Capital, Cashflow, Decisiones, Negocios, Metas) |
| `Esc` | Cerrar drawer / paleta / confirmación |
| `↑` `↓` `⏎` | Navegar resultados de la paleta |

## Cómo probar la v0.5 (smoke test)

Antes de subir a Pages, probá local:

```bash
python -m http.server 5173
# abrir http://localhost:5173
```

**1. Verificación de migración (si venís de v0.4):**
- Al abrir, deberías ver toast verde: "Datos v0.4 migrados a v0.5"
- Andá a Decisiones — deberías ver tu data v0.4 + el demo de "Mazda 3 sport 2025" guardado

**2. Probar una decisión nueva:**
- Decisiones → click "Comprar auto"
- Drawer abre con inputs precargados
- Cambiá `Precio` a 22000000 — el veredicto debería recalcularse al instante
- Cambiá `Pie` a 8000000 — flujo libre post se actualiza
- Bajá `Pie` a 1000000 — ahora debería marcar "No ahora" porque cash queda muy bajo
- Mirá las condiciones: te dice cuánto más cash necesitarías

**3. Guardar una decisión:**
- Cambiá el nombre a "Mazda 3 con pie alto"
- Agregá notas: "Esperar bono de fin de año"
- Click Guardar → drawer cierra, toast "Decisión guardada"
- Volvé a Decisiones — debería aparecer en la tabla de "Decisiones guardadas" con su veredicto

**4. Editar una guardada:**
- Click en la fila guardada → drawer reabre con tus inputs
- Cambiá algo, guardá. Verificá que se actualiza.

**5. Eliminar:**
- Click en una guardada → botón rojo "Eliminar" abajo a la izquierda → confirmar.

**6. Probar las otras 7 plantillas:**
- Recorrelas. Cada una debería abrir, calcular sin NaN, mostrar veredicto.
- Especialmente `Cambiar trabajo`: poné `Meses sin ingreso = 3` y mirá el warning sobre runway.

**7. Impacto en metas:**
- Asegurate de tener al menos una meta activa (Metas → + Meta si hace falta).
- Volvé a Decisiones, abrí "Comprar auto" → la sección "Impacto en metas" debe mostrar +/- meses por cada meta.

**8. Respaldo:**
- Topbar → "Respaldo" → descarga `wealth-os-YYYY-MM-DD.json`
- Verificá que el JSON tiene un array `decisions` con tus decisiones guardadas

**9. Paleta:**
- ⌘K → escribí "decisión" → debería aparecer "Nueva decisión" + las acciones de crear entidad

**10. Migración desde v0.3:**
- Si limpiás `localStorage` y solo dejás la key `wealth_os_v03`, al cargar debería migrar a v0.5

## Si algo falla

Consola del navegador (F12) — cualquier `TypeError`, `undefined` o `NaN` es bug. Reportame qué tocaste y qué pasó.

Reset total: ⌘K → "Borrar todo" o `localStorage.clear(); location.reload()`.

## Estructura del repo

```
Finanzas/
├── backups/v0.2/     ← se mantiene
├── index.html        ← v0.5
├── manifest.json     ← v05
├── sw.js             ← cache v05
├── icon.svg
├── README.md         ← este archivo
├── ARCHITECTURE.md   ← se mantiene
└── schema.sql        ← se mantiene
```

## Lo que NO está en v0.5 (postergado)

- **Venture Lab con escenarios downside/base/upside** (queda para Slice 2 si lo retomamos).
- **Comparación lado-a-lado de decisiones** (sería una v0.6: tomar 2-3 decisiones guardadas y ver cuál destruye/acelera más las metas).
- **Gráfico de proyección de patrimonio** (hoy es solo numérico 12/24/36m; un mini-chart en el drawer ayudaría).
- **Toggle de supuestos del modelo** (hoy es 6% sobre invertidos, 3% sobre RE — debería ser configurable por escenario).

## Stack

HTML + CSS + JS vanilla. Sin frameworks. ~137KB total. localStorage. Service Worker para offline. PWA instalable.

## Privacidad

Todo vive en `localStorage` del navegador. Cero servidor, cero analytics, cero terceros. Hacé respaldo regular.
