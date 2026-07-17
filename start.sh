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
# 2. Flutter dependencies
# ---------------------------------------------------------------------------
echo ""
echo "🔧 Fetching Flutter dependencies..."
cd athar_frontend
flutter pub get --suppress-analytics

# ---------------------------------------------------------------------------
# 3. Flutter web build — skipped when the build is already up-to-date.
#
#    We compare a hash of the Dart source files + pubspec + dart-defines
#    against a stamp file saved inside the build output. If they match,
#    the existing build is reused and startup takes ~5 s instead of ~2 min.
#    Any change to lib/, pubspec.yaml, pubspec.lock, or the dart-define
#    values (API URL, Supabase keys) invalidates the stamp automatically.
# ---------------------------------------------------------------------------
BUILD_DIR="build/web"
STAMP_FILE="${BUILD_DIR}/.build_stamp"

# Dart-define values that affect the compiled output
DART_DEFINES="API_BASE_URL=${ORIGIN} SUPABASE_URL=${SUPABASE_URL:-} SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}"

# Hash: Dart sources + pubspec files + dart-define values
CURRENT_HASH=$(find lib assets pubspec.yaml pubspec.lock -type f \
  -not -path '**/__pycache__/*' \
  | sort | xargs md5sum 2>/dev/null | md5sum | awk '{print $1}')
CURRENT_HASH="${CURRENT_HASH}_$(echo "$DART_DEFINES" | md5sum | awk '{print $1}')"

SAVED_HASH=""
if [ -f "$STAMP_FILE" ]; then
  SAVED_HASH=$(cat "$STAMP_FILE")
fi

if [ "$CURRENT_HASH" = "$SAVED_HASH" ] && [ -f "${BUILD_DIR}/index.html" ]; then
  echo "⚡ Flutter build is up-to-date — skipping rebuild."
else
  echo ""
  echo "🏗️  Building Flutter web (first run or source changed)..."
  flutter build web \
    --suppress-analytics \
    --dart-define=API_BASE_URL="${ORIGIN}" \
    --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
    --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

  # Save the new stamp so the next restart can skip the build
  echo "$CURRENT_HASH" > "$STAMP_FILE"
  echo ""
  echo "✅ Flutter build complete."
fi

cd ..

# ---------------------------------------------------------------------------
# 4. Start FastAPI on port 5000
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
