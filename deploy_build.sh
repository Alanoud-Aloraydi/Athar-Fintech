#!/usr/bin/env bash
# Production build script — runs once during the Replit publish step.
# Installs dependencies and compiles the Flutter web app.
set -e

echo "🌴 Athar FinTech — Production Build"
echo ""

# ---------------------------------------------------------------------------
# 1. Python dependencies
# ---------------------------------------------------------------------------
echo "🔧 Installing Python dependencies..."
pip install -q -r backend/requirements.txt

# ---------------------------------------------------------------------------
# 2. Flutter dependencies
# ---------------------------------------------------------------------------
echo "🔧 Fetching Flutter dependencies..."
cd athar_frontend
flutter pub get --suppress-analytics

# ---------------------------------------------------------------------------
# 3. Flutter web build
#
# API_BASE_URL is intentionally omitted: ApiService detects the host at
# runtime via Uri.base, so the binary works correctly on any domain
# (dev *.replit.dev or prod *.replit.app) without hardcoding URLs.
# ---------------------------------------------------------------------------
echo ""
echo "🏗️  Building Flutter web for production..."
flutter build web \
  --suppress-analytics \
  --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

cd ..
echo ""
echo "✅ Production build complete."
