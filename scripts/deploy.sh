#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/site/"
ACTIVATE="${ROOT}/scripts/activate.sh"

usage() {
  cat <<'EOF'
Uso:
  scripts/deploy.sh --local DESTINO [--dry-run]
  DEPLOY_HOST=... DEPLOY_USER=... DEPLOY_PATH=... scripts/deploy.sh [--dry-run]

Copia site/ para DESTINO/releases/<stamp>/ e só então aponta o symlink
DESTINO/current para esse release. Não usa --delete na pasta ao vivo.

--local não abre SSH. Sem --local, o destino é user@host:DEPLOY_PATH.
O caminho precisa ser absoluto, com pelo menos duas pastas, sem espaço,
e não pode ser a raiz de um diretório do sistema.

DEPLOY_RELOAD=1 pede, no servidor, que o root do nginx seja DEPLOY_PATH/current
antes de trocar o symlink. Depois troca e roda sudo nginx -t && sudo systemctl reload nginx.
Se o reload falhar, current volta para o release anterior.
EOF
}

refuse_broad_path() {
  local path="$1"
  local label="$2"
  if [[ ! "$path" =~ ^/[A-Za-z0-9._/-]+$ || "$path" == *..* || "$path" == *//* ]]; then
    echo "$label precisa ser absoluto, sem .. e sem espaço: $path" >&2
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

make_stamp() {
  printf '%s-%s\n' "$(date -u +%Y%m%d%H%M%S)" "$$${RANDOM}$(date +%N)"
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

rsync_sync=(rsync -a --delete --human-readable --exclude '.DS_Store')

publish_tree() {
  local dest="$1"
  local reload_flag="$2"
  local stamp
  local rel
  stamp="$(make_stamp)"
  rel="${dest}/releases/${stamp}"
  if [[ "$dry_run" -eq 1 ]]; then
    if [[ -d "${dest}/current" ]]; then
      rsync -a --delete --dry-run --itemize-changes --human-readable --exclude '.DS_Store' \
        "$SRC" "${dest}/current/"
    else
      echo "dry-run: primeiro release em ${dest}/releases/${stamp}, sem gravar"
    fi
    return 0
  fi
  mkdir -p "$rel"
  "${rsync_sync[@]}" "$SRC" "${rel}/"
  bash "$ACTIVATE" "$dest" "$stamp" "$reload_flag"
}

if [[ -n "$local_dest" ]]; then
  local_dest="${local_dest%/}"
  refuse_broad_path "$local_dest" "--local"
  publish_tree "$local_dest" 0
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
case "${DEPLOY_RELOAD:-0}" in
  0|1) ;;
  *) echo "DEPLOY_RELOAD deve ser 0 ou 1" >&2; exit 2 ;;
esac

DEPLOY_PATH="${DEPLOY_PATH%/}"
refuse_broad_path "$DEPLOY_PATH" "DEPLOY_PATH"

remote="${DEPLOY_USER}@${DEPLOY_HOST}"
stamp="$(make_stamp)"

if [[ "$dry_run" -eq 1 ]]; then
  if ssh -o BatchMode=yes "$remote" "test -d '${DEPLOY_PATH}/current'"; then
    rsync -a --delete --dry-run --itemize-changes --human-readable --exclude '.DS_Store' \
      -e "ssh -o BatchMode=yes" "$SRC" "${remote}:${DEPLOY_PATH}/current/"
  else
    echo "dry-run: ainda não há current. o envio criaria ${DEPLOY_PATH}/releases/${stamp}/"
  fi
  exit 0
fi

ssh -o BatchMode=yes "$remote" "mkdir -p '${DEPLOY_PATH}/releases/${stamp}'"
"${rsync_sync[@]}" -e "ssh -o BatchMode=yes" "$SRC" "${remote}:${DEPLOY_PATH}/releases/${stamp}/"
ssh -o BatchMode=yes "$remote" "bash -s -- '${DEPLOY_PATH}' '${stamp}' '${DEPLOY_RELOAD:-0}'" < "$ACTIVATE"
