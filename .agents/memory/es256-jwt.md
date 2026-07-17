---
name: ES256 JWT & cryptography package
description: Supabase projects sign JWTs with ES256 (asymmetric); PyJWT requires the `cryptography` package to verify them.
---

## The rule
`cryptography==44.0.3` must be in `backend/requirements.txt` (and installed) or PyJWT's JWKS path silently returns `None`, making every authenticated request return 401.

## Why
Supabase uses ES256 (asymmetric / JWKS) for JWT signing by default. PyJWT only supports ES256 verification if the `cryptography` package is present. Without it, no error is raised — the JWKS fetch silently fails and no user is authenticated.

## How to apply
Already done: `cryptography==44.0.3` is in `requirements.txt`. Start script installs it via `pip install -r requirements.txt`.
