#!/usr/bin/env bash
set -e

echo ""
echo "🌴 ===== Athar FinTech — Build & Start ====="
echo ""

# ---------------------------------------------------------------------------
# Public origin — same URL for Flutter web AND the API (single port: 5000)
# ---------------------------------------------------------------------------
ORIGIN="https://${REPLIT_DEV_DOMAIN:-localhost:5000}"
echo "📡 Public origin: ${ORIGIN}"
echo ""

# ---------------------------------------------------------------------------
# 1. Python dependencies
# ---------------------------------------------------------------------------
echo "🔧 Installing Python dependencies..."
pip install -q -r backend/requirements.txt

# ---------------------------------------------------------------------------
# 2. Flutter web build
#    API_BASE_URL = same origin (FastAPI serves on port 5000 = same host)
# ---------------------------------------------------------------------------
echo ""
echo "🔧 Fetching Flutter dependencies..."
cd athar_frontend
flutter pub get --suppress-analytics

echo ""
echo "🏗️  Building Flutter web (this takes ~2-3 min on first run)..."
flutter build web \
  --suppress-analytics \
  --dart-define=API_BASE_URL="${ORIGIN}" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"
cd ..

echo ""
echo "✅ Flutter build complete."

# ---------------------------------------------------------------------------
# 3. Start FastAPI on port 5000
#    — serves the API routes AND the Flutter web SPA via catch-all
# ---------------------------------------------------------------------------
# pydantic-settings v2 expects list[str] env vars as JSON arrays.
export CORS_ORIGINS='["'"${ORIGIN}"'","http://localhost:5000"]'

echo ""
echo "🚀 Starting FastAPI on port 5000 (API + Flutter web)..."
echo "   Swagger UI → ${ORIGIN}/docs"
echo "   Flutter app → ${ORIGIN}/"
echo ""

cd backend
uvicorn app.main:app \
  --host 0.0.0.0 \
  --port 5000 \
  --log-level info
