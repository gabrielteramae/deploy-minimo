#!/usr/bin/env bash
# Ativa um release já copiado em BASE/releases/STAMP.
# Uso: activate.sh BASE STAMP [0|1]
# Com 1, lê o root do nginx antes de trocar o symlink e recarrega.
# Se o reload falhar, current volta para o release anterior.
set -euo pipefail

base="${1:?falta BASE}"
stamp="${2:?falta STAMP}"
do_reload="${3:-0}"

if [[ "$base" != /* || "$base" == *..* || "$base" == *//* ]]; then
  echo "BASE inválido: $base" >&2
  exit 2
fi
if [[ ! "$base" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
  echo "BASE inválido: $base" >&2
  exit 2
fi
if [[ ! "$stamp" =~ ^[0-9]{14}-[0-9]+$ ]]; then
  echo "STAMP inválido: $stamp" >&2
  exit 2
fi
if [[ "$do_reload" != "0" && "$do_reload" != "1" ]]; then
  echo "reload deve ser 0 ou 1" >&2
  exit 2
fi

release="${base}/releases/${stamp}"
if [[ ! -d "$release" ]]; then
  echo "release ausente: $release" >&2
  exit 2
fi
if [[ -e "${base}/current" && ! -L "${base}/current" ]]; then
  echo "current existe e não é symlink: ${base}/current" >&2
  exit 2
fi

expected="${base}/current"

nginx_serves() {
  local conf="$1"
  local expect="$2"
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == "root ${expect};" ]]; then
      return 0
    fi
  done <<<"$conf"
  return 1
}

read_nginx_dump() {
  if [[ -n "${ACTIVATE_NGINX_DUMP:-}" ]]; then
    cat "$ACTIVATE_NGINX_DUMP"
    return 0
  fi
  local err
  err="$(mktemp)"
  if ! sudo nginx -T 2>"$err"; then
    cat "$err" >&2
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
}

run_reload() {
  if [[ -n "${ACTIVATE_RELOAD_CMD:-}" ]]; then
    bash -c "$ACTIVATE_RELOAD_CMD"
    return
  fi
  sudo nginx -t && sudo systemctl reload nginx
}

restore_previous() {
  local prev="$1"
  if [[ -n "$prev" ]]; then
    ln -sfn "$prev" "${base}/current.next"
    mv -Tf "${base}/current.next" "${base}/current"
  else
    rm -f "${base}/current"
  fi
}

prune_releases() {
  local keep=5
  local -a dirs=()
  local name
  local count
  local drop
  local i
  list="$(find "${base}/releases" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)"
  while IFS= read -r name; do
    [[ -n "$name" ]] && dirs+=("$name")
  done <<EOF
$list
EOF
  count="${#dirs[@]}"
  if (( count <= keep )); then
    return 0
  fi
  drop=$((count - keep))
  for ((i = 0; i < drop; i++)); do
    rm -rf "${base}/releases/${dirs[$i]}"
  done
}

if [[ "$do_reload" == "1" ]]; then
  conf="$(read_nginx_dump)" || exit 1
  if ! nginx_serves "$conf" "$expected"; then
    echo "nginx não serve ${expected}" >&2
    exit 3
  fi
fi

prev=""
if [[ -L "${base}/current" ]]; then
  prev="$(readlink "${base}/current")"
fi

ln -sfn "releases/${stamp}" "${base}/current.next"
mv -Tf "${base}/current.next" "${base}/current"

if [[ "$do_reload" == "1" ]]; then
  if ! run_reload; then
    restore_previous "$prev"
    echo "reload falhou; symlink voltou para o release anterior" >&2
    exit 1
  fi
fi

prune_releases
