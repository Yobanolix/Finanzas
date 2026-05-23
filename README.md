# Wealth OS v0.3

Personal PWA for capital, cashflow, decisions and venture planning.

## What changed

- Fewer modules with stronger utility: Today, Capital, Cashflow, Decision Lab and Venture Lab.
- Capital supports cash, mutual funds, ETFs, stocks, APV, real estate, private assets and other assets.
- Decision Lab simulates personal decisions such as buying a car, buying a second property, starting a business, investing more or prepaying debt.
- Venture Lab models a family business with products, unit economics, fixed costs, gross margin, net margin, break-even, runway, payback and ownership structure.
- Goals are not a separate module. They are a layer inside decisions.

## Local use

Open `index.html` directly in a browser.

For PWA install/offline behavior, serve the folder locally:

```powershell
python -m http.server 5173
```

Then open:

```text
http://localhost:5173
```

## GitHub Pages

Commit these files to the root of a GitHub Pages repo:

- `index.html`
- `manifest.json`
- `sw.js`
- `icon.svg`
- `README.md`

Then enable Pages from the repository settings.

## Data

All data is stored locally in `localStorage`.

Use the `Backup` button to export JSON. Drag a backup JSON anywhere onto the app to import it.
