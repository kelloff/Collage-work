#!/usr/bin/env bash
# Деплой бэкенда на VPS (Ubuntu/Debian). Запуск на сервере от root или с sudo.
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/collage-work}"
BECK_DIR="$APP_ROOT/beck"
SERVICE_NAME="collage-backend"
REPO_SRC="${1:-}"

if [[ -z "$REPO_SRC" ]]; then
  echo "Usage: sudo ./deploy_backend.sh /path/to/Collage-work"
  echo "  or set REPO_SRC and run from checkout on server."
  exit 1
fi

echo "==> Sync beck/ -> $BECK_DIR"
mkdir -p "$APP_ROOT"
rsync -a --delete \
  --exclude 'env/' \
  --exclude '__pycache__/' \
  --exclude 'tasks_pool.json' \
  --exclude '.env' \
  "$REPO_SRC/beck/" "$BECK_DIR/"

if [[ ! -f "$BECK_DIR/.env" ]]; then
  echo "==> Create .env from env.example"
  cp "$BECK_DIR/env.example" "$BECK_DIR/.env"
  chown www-data:www-data "$BECK_DIR/.env"
  chmod 640 "$BECK_DIR/.env"
  echo "    Edit $BECK_DIR/.env before production traffic."
fi

echo "==> Python venv"
if [[ ! -x "$BECK_DIR/env/bin/python" ]]; then
  python3 -m venv "$BECK_DIR/env"
fi
"$BECK_DIR/env/bin/pip" install -q -r "$BECK_DIR/requirements.txt"

echo "==> systemd unit"
install -m 644 "$(dirname "$0")/collage-backend.service" "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo "==> Health (local)"
sleep 2
curl -sf "http://127.0.0.1:8000/health" | head -c 400
echo ""
echo "Done. Public: curl -s https://YOUR_DOMAIN/health"
