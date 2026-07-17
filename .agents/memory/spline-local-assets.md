---
name: Spline runtime vendoring
description: Vendoring the Spline runtime for offline use requires patching CDN base-URL strings inside runtime.js and downloading all WASM binaries alongside the JS chunks.
---

## The rule
When vendoring the Spline runtime locally, you must:
1. Download all chunk JS files (`boolean.js`, `navmesh.js`, `process.js`, `ui.js`, `howler.js`, `opentype.js`, `physics.js`, `gaussian-splat-compression.js`) AND the four WASM binaries (`boolean.wasm`, `navmesh.wasm`, `process.wasm`, `ui.wasm`).
2. Patch `runtime.js`: replace CDN base-URL strings with `"."` (relative). The pattern is `!1 ? "." : "https://unpkg.com/..."` — minified `!1` is `false`, so it always picks CDN. Replace the CDN string literal directly.
3. Add `'wasm-unsafe-eval'` to `script-src` in the CSP.
4. Serve WASM files with `application/wasm` MIME type (FastAPI's `mimetypes.guess_type` handles this automatically for `.wasm`).

## Why
Spline's runtime.js hardcodes CDN base URLs for navmesh, modelling (process), boolean, and UI (skia) WASM. Without patching, these fetches are blocked by the app's `connect-src` CSP. The chunk JS files load their WASM via relative paths (`process.wasm`, `navmesh.wasm`, etc.) — so placing the WASM files in the same directory as the JS files and patching the base URL to `"."` makes everything resolve locally.

## How to apply
```python
replacements = [
    ('"https://unpkg.com/@splinetool/navmesh-wasm@X.Y.Z/build"', '"."'),
    ('"https://unpkg.com/@splinetool/navmesh-wasm@X.Y.Z/build/"', '"."'),
    ('"https://unpkg.com/@splinetool/modelling-wasm@X.Y.Z/build"', '"."'),
    ('"https://unpkg.com/@splinetool/boolean-wasm@X.Y.Z/build"', '"."'),
    ('"https://unpkg.com/@splinetool/ui-wasm@X.Y.Z/build/ui.wasm"', '"./ui.wasm"'),
    ('"https://unpkg.com/@splinetool/runtime@X.Y.Z/build/"', '"./"'),
]
```

## Flutter web asset path
Flutter web serves assets at `/assets/<pubspec-path>`. If pubspec declares `assets/oasis/`, the oasis viewer HTML is at `/assets/assets/oasis/oasis_viewer.html` (the double `assets/` is correct — Flutter web prepends `/assets/` to the pubspec path).

## Build stamp
The `start.sh` stamp hashes `find lib assets pubspec.yaml pubspec.lock`. New files added to `assets/oasis/` DO invalidate the stamp (assets dir is included in the hash). The post-merge script deletes the stamp after each task merge to force a full rebuild.
