# Memory index

- [Transaction write bug & fix](tx-write-bug.md) — migration 002's create_transaction_atomic missing ::category_type cast; repo now uses table-level ops; migration 005 has the corrected SQL.
- [ES256 JWT & cryptography](es256-jwt.md) — Supabase uses ES256 asymmetric JWTs; `cryptography` package must be installed or PyJWT JWKS path silently returns None.
- [Spline runtime vendoring](spline-local-assets.md) — runtime.js needs all sibling chunks vendored; Flutter web assets live under /assets/assets/; FastAPI catch-all must set explicit MIME.
