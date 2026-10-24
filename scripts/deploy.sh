#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/site/"

usage() {
  cat <<'EOF'
Uso:
  scripts/deploy.sh --local DESTINO [--dry-run]
  DEPLOY_HOST=... DEPLOY_USER=... DEPLOY_PATH=... scripts/deploy.sh [--dry-run]

Copia o conteúdo de site/ com rsync.
--local não abre SSH. Sem --local, o destino é user@host:path.
DEPLOY_RELOAD=1, depois do envio, roda no servidor: sudo nginx -t && sudo systemctl reload nginx
EOF
}

dry_run=0
local_dest=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --local)
      [[ $# -ge 2 ]] || { echo "falta o destino de --local" >&2; exit 2; }
      local_dest="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; usage >&2; exit 2 ;;
  esac
done

rsync_cmd=(rsync -a --delete --human-readable --exclude '.DS_Store')
if [[ "$dry_run" -eq 1 ]]; then
  rsync_cmd+=(--dry-run --itemize-changes)
fi

if [[ -n "$local_dest" ]]; then
  mkdir -p "$local_dest"
  "${rsync_cmd[@]}" "$SRC" "${local_dest%/}/"
  exit 0
fi

: "${DEPLOY_HOST:?defina DEPLOY_HOST}"
: "${DEPLOY_USER:?defina DEPLOY_USER}"
: "${DEPLOY_PATH:?defina DEPLOY_PATH}"

remote="${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH%/}/"
"${rsync_cmd[@]}" -e "ssh -o BatchMode=yes" "$SRC" "$remote"

if [[ "${DEPLOY_RELOAD:-0}" == "1" && "$dry_run" -eq 0 ]]; then
  ssh -o BatchMode=yes "${DEPLOY_USER}@${DEPLOY_HOST}" "sudo nginx -t && sudo systemctl reload nginx"
fi
