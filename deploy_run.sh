#!/usr/bin/env bash
# Production run script — starts FastAPI (serves Flutter web + API).
set -e

# Allow requests from the production domain(s).
# REPLIT_DOMAINS contains the *.replit.app hostname(s); fall back to a
# reasonable default if the variable is not set.
FIRST_DOMAIN=$(echo "${REPLIT_DOMAINS:-athar-fintech.replit.app}" | cut -d',' -f1)
ORIGIN="https://${FIRST_DOMAIN}"

export CORS_ORIGINS='["'"${ORIGIN}"'"]'

echo "🚀 Starting FastAPI (production) on port 5000..."
echo "   Origin: ${ORIGIN}"
echo ""

cd backend
exec uvicorn app.main:app \
  --host 0.0.0.0 \
  --port 5000 \
  --log-level info
