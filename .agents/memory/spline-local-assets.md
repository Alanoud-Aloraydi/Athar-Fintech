---
name: Spline runtime vendoring
description: How the Spline 3D runtime is vendored locally and pitfalls when serving it
---

# Spline runtime vendoring (oasis viewer)

- The Spline runtime is not a single file: `runtime.js` lazily imports sibling chunks (`process.js`, `physics.js`, `ui.js`, `boolean.js`, `howler.js`, `navmesh.js`, `opentype.js`, `gaussian-splat-compression.js`). All must be vendored next to it or the module import fails with a MIME error (missing chunk falls through to the SPA catch-all and returns index.html).
- **Why:** unpkg CDN outage/offline mode made the 3D scene fail; vendored everything into `athar_frontend/assets/oasis/`.
- Flutter web serves bundled assets under `/assets/assets/<asset-key>` — iframe URLs must use the double `assets/assets/` prefix.
- The FastAPI SPA catch-all must pass an explicit `media_type` to `FileResponse` (mimetypes.guess_type) — module scripts are MIME-checked strictly.
- `curl -I` (HEAD) against GET-only FastAPI routes returns a 405 with `application/json` — use GET when checking content types, or HEAD results mislead.
- The runtime version must be >= the `.splinecode` scene format version (warning "file is more recent than the library"); vendor the latest `@splinetool/runtime` build when updating scenes.
- Headless screenshot browser has no WebGL — the scene shows its fallback there; that is not an app bug.
