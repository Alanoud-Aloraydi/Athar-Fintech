# =============================================================================
# Athar-Fintech — single-image deployment (Flutter web + FastAPI on one URL)
#
# Stage 1 compiles the Flutter web app; stage 2 is a slim Python image that
# runs FastAPI (uvicorn) and serves the compiled web build from the same
# origin — so the browser talks to the API and the app on one host, no CORS.
#
# The frontend detects its own origin at runtime (Uri.base), so the ONLY
# build-time values it needs are the Supabase client keys. On Render these
# are provided automatically as build args from the service's env vars.
# =============================================================================

# ---- Stage 1: build the Flutter web bundle ----------------------------------
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-build

# Supabase client config baked into the web build (anon key is public-safe).
ARG SUPABASE_URL=""
ARG SUPABASE_ANON_KEY=""

WORKDIR /app/athar_frontend

# Copy the whole frontend and fetch packages, then compile.
COPY athar_frontend/ ./
RUN git config --global --add safe.directory /sdks/flutter || true
RUN flutter pub get --suppress-analytics
RUN flutter build web --release --suppress-analytics \
      --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
      --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"

# ---- Stage 2: Python runtime that serves API + web --------------------------
FROM python:3.12-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Python dependencies first (better layer caching).
COPY backend/requirements.txt backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt

# Backend source.
COPY backend/ backend/

# Bring in the compiled web app at exactly the path main.py serves from:
#   backend/app/main.py -> parents[2] == /app  ->  /app/athar_frontend/build/web
COPY --from=flutter-build /app/athar_frontend/build/web athar_frontend/build/web

# Render (and most PaaS) inject the listening port via $PORT; default to 5000.
ENV PORT=5000
EXPOSE 5000

# Start FastAPI. __file__-based paths in main.py are absolute, so the cd is
# only to keep the app-import path (app.main:app) resolvable.
CMD ["sh", "-c", "cd backend && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-5000} --log-level info"]
