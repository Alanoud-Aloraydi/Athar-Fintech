# Athar Frontend (أَثر)

Flutter Web frontend for the Athar FinTech application.

## What it does

Renders the user's financial health as a **live 3D Palm Tree Oasis** powered by Spline. The app is fully bilingual (Arabic/English) and communicates with the FastAPI backend for all financial data.

## Screens

| Screen | File | Description |
|--------|------|-------------|
| Login | `login_screen.dart` | Supabase Auth sign-in / sign-up |
| Dashboard | `dashboard_screen.dart` | Current balance, savings wallet, active goal CTA |
| Oasis (واحة) | `farm_screen.dart` | 3D palm scene + goal lifecycle buttons |
| Transactions | `transactions_screen.dart` | Spending history with category chips |
| Profile | `profile_screen.dart` | Account info + completed goal history |

## Key Architecture Notes

- **Single source of truth**: `farm_screen.dart` fetches `getDashboardSummary()` (same endpoint as the Dashboard tab) to drive the 3D scene — guarantees wallet balance, palm count, and health filter are always in sync.
- **Spline assets are fully vendored** in `assets/oasis/` (`runtime.js` + `scene.splinecode` + WASM modules). No CDN requests at runtime.
- **Oasis sync**: `palm_oasis_viewer.dart` exposes `updateOasisState({progress, health})`. The scene host (`oasis_viewer.html`) listens for `postMessage` commands on web and `window.updateOasisState` on native.

## Running

This app is built and served by the root `start.sh` as part of the full Athar stack. To iterate on Flutter only:

```bash
cd athar_frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5000 \
  --dart-define=SUPABASE_URL=<url> \
  --dart-define=SUPABASE_ANON_KEY=<key>
```

## Tests

```bash
flutter test
```
