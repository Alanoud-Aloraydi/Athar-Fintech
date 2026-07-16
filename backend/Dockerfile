# syntax=docker/dockerfile:1
FROM python:3.11-slim AS base

# Prevents .pyc files + forces stdout/stderr to be unbuffered (required for DO log capture)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Install deps first for layer caching — code changes won't invalidate this layer
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code (venv/, __pycache__, .env excluded via .dockerignore)
COPY app ./app

# Non-root user — DO App Platform and general container hardening best practice
RUN addgroup --system athar && adduser --system --ingroup athar athar
USER athar

# DigitalOcean App Platform injects $PORT at runtime; default to 8080 for local `docker run`
ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,os; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",8080)}/health').read()" || exit 1

# Shell form via sh -c so ${PORT} is actually expanded at container start
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080} --proxy-headers"]