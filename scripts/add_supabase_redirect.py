#!/usr/bin/env python3
"""
Configure Supabase redirect URLs for password-reset email links.

Usage:
    SUPABASE_MGMT_TOKEN=<your-token> python3 scripts/add_supabase_redirect.py

The management token is a *personal access token* from:
    https://supabase.com/dashboard/account/tokens

It is NOT the project's service key.
"""

import os
import sys
import json
import urllib.request
import urllib.error

# ── Config ──────────────────────────────────────────────────────────────────
SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
MGMT_TOKEN = os.environ.get("SUPABASE_MGMT_TOKEN", "")
DEV_DOMAIN = os.environ.get("REPLIT_DEV_DOMAIN", "")

if not SUPABASE_URL:
    print("❌  SUPABASE_URL env var is not set.", file=sys.stderr)
    sys.exit(1)

if not MGMT_TOKEN:
    print("❌  SUPABASE_MGMT_TOKEN env var is not set.", file=sys.stderr)
    print("   Generate one at https://supabase.com/dashboard/account/tokens", file=sys.stderr)
    sys.exit(1)

# Extract project ref from https://<ref>.supabase.co
project_ref = SUPABASE_URL.replace("https://", "").split(".")[0]
if not project_ref:
    print("❌  Could not extract project ref from SUPABASE_URL.", file=sys.stderr)
    sys.exit(1)

# ── Build redirect URL list ──────────────────────────────────────────────────
urls_to_add: list[str] = []

if DEV_DOMAIN:
    urls_to_add.append(f"https://{DEV_DOMAIN}")

# Fetch existing config first so we can merge, not overwrite
mgmt_api = f"https://api.supabase.com/v1/projects/{project_ref}/config/auth"
headers = {
    "Authorization": f"Bearer {MGMT_TOKEN}",
    "Content-Type": "application/json",
}

print(f"📡  Project ref   : {project_ref}")
print(f"🌐  Dev domain    : https://{DEV_DOMAIN}" if DEV_DOMAIN else "⚠️   REPLIT_DEV_DOMAIN not set — skipping dev URL")
print()

# GET current config
req = urllib.request.Request(mgmt_api, headers=headers, method="GET")
try:
    with urllib.request.urlopen(req) as resp:
        current = json.loads(resp.read())
except urllib.error.HTTPError as exc:
    body = exc.read().decode()
    print(f"❌  GET {mgmt_api} → HTTP {exc.code}: {body}", file=sys.stderr)
    sys.exit(1)

existing_raw: str = current.get("uri_allow_list", "") or ""
existing: list[str] = [u.strip() for u in existing_raw.split(",") if u.strip()]

print(f"🔍  Existing redirect URLs ({len(existing)}):")
for u in existing:
    print(f"    • {u}")
print()

# Merge
merged = list(existing)
added = []
for url in urls_to_add:
    if url not in merged:
        merged.append(url)
        added.append(url)

if not added:
    print("✅  All required URLs are already whitelisted — nothing to do.")
    sys.exit(0)

print(f"➕  Adding {len(added)} new URL(s):")
for u in added:
    print(f"    • {u}")
print()

# PATCH
payload = json.dumps({"uri_allow_list": ",".join(merged)}).encode()
req2 = urllib.request.Request(mgmt_api, data=payload, headers=headers, method="PATCH")
try:
    with urllib.request.urlopen(req2) as resp:
        updated = json.loads(resp.read())
except urllib.error.HTTPError as exc:
    body = exc.read().decode()
    print(f"❌  PATCH {mgmt_api} → HTTP {exc.code}: {body}", file=sys.stderr)
    sys.exit(1)

new_list = [u.strip() for u in (updated.get("uri_allow_list") or "").split(",") if u.strip()]
print("✅  Supabase redirect URLs updated successfully!")
print(f"\n🔗  Full allow-list ({len(new_list)}):")
for u in new_list:
    print(f"    • {u}")
print()
print("Next: test the full password-reset round trip in the app.")
