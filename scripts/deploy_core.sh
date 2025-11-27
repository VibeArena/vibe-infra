#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../compose/core"

# Ensure env file exists (copy example if needed)
[ -f ../../env/.env.core ] || cp ../../env/.env.core.example ../../env/.env.core

docker compose pull
docker compose up -d
docker compose ps
