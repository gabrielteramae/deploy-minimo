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
O caminho precisa ser absoluto, com pelo menos duas pastas, e não pode ser a raiz de um diretório do sistema.
DEPLOY_RELOAD=1, depois do envio, roda no servidor: sudo nginx -t && sudo systemctl reload nginx
EOF
}

refuse_broad_path() {
  local path="$1"
  local label="$2"
  if [[ "$path" != /* || "$path" == *..* ]]; then
    echo "$label precisa ser absoluto e sem ..: $path" >&2
    exit 2
  fi
  case "$path" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var|/var/www|/usr/share|/usr/share/nginx|/usr/share/nginx/html)
      echo "$label recusado: $path" >&2
      exit 2
      ;;
  esac
  local trimmed="${path#/}"
  local segments=0
  local part
  IFS=/ read -ra parts <<<"$trimmed"
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] && segments=$((segments + 1))
  done
  if [[ "$segments" -lt 2 ]]; then
    echo "$label curto demais: $path" >&2
    exit 2
  fi
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
  local_dest="${local_dest%/}"
  refuse_broad_path "$local_dest" "--local"
  mkdir -p "$local_dest"
  "${rsync_cmd[@]}" "$SRC" "${local_dest}/"
  exit 0
fi

: "${DEPLOY_HOST:?defina DEPLOY_HOST}"
: "${DEPLOY_USER:?defina DEPLOY_USER}"
: "${DEPLOY_PATH:?defina DEPLOY_PATH}"

if [[ ! "$DEPLOY_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
  echo "DEPLOY_HOST inválido" >&2
  exit 2
fi
if [[ ! "$DEPLOY_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "DEPLOY_USER inválido" >&2
  exit 2
fi

DEPLOY_PATH="${DEPLOY_PATH%/}"
refuse_broad_path "$DEPLOY_PATH" "DEPLOY_PATH"

remote="${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/"
"${rsync_cmd[@]}" -e "ssh -o BatchMode=yes" "$SRC" "$remote"

if [[ "${DEPLOY_RELOAD:-0}" == "1" && "$dry_run" -eq 0 ]]; then
  ssh -o BatchMode=yes "${DEPLOY_USER}@${DEPLOY_HOST}" "sudo nginx -t && sudo systemctl reload nginx"
fi
