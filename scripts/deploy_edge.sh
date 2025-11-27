#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../compose/edge"

# Ensure env file exists (copy example if needed)
[ -f ../../env/.env.edge ] || cp ../../env/.env.edge.example ../../env/.env.edge

docker compose pull
docker compose up -d
docker compose ps
