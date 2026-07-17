#!/usr/bin/env bash
# Post-merge setup script — runs automatically after every task merge.
# Installs/updates dependencies so the workspace is ready.
# The "Start application" workflow is restarted automatically afterwards,
# which triggers start.sh and does the full Flutter web build.
set -e

echo "🔧 [post-merge] Installing Python dependencies..."
pip install -q -r backend/requirements.txt

echo "🔧 [post-merge] Fetching Flutter dependencies..."
cd athar_frontend
flutter pub get --suppress-analytics
cd ..

echo "✅ [post-merge] Dependencies ready."
