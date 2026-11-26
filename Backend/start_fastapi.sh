#!/usr/bin/env bash

set -euo pipefail

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$backend_dir"

if [[ ! -x "venv/bin/python" ]]; then
  echo "Missing Backend/venv. Create it and install requirements first." >&2
  exit 1
fi

if [[ ! -f ".env" ]]; then
  echo "Missing Backend/.env. Copy .env.example and configure it first." >&2
  exit 1
fi

if [[ ! -f "app/model_weights/tme_nuclei_v2/model.pt" ]]; then
  echo "Missing the installed TME-Insight model bundle." >&2
  exit 1
fi

exec venv/bin/python -m uvicorn main:app \
  --host "${TME_API_HOST:-0.0.0.0}" \
  --port "${TME_API_PORT:-8000}"
