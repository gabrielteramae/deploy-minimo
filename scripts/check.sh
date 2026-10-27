#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
deploy="${ROOT}/scripts/deploy.sh"
activate="${ROOT}/scripts/activate.sh"

bash -n "$deploy"
bash -n "$activate"

expect_reject() {
  local name="$1"
  shift
  set +e
  "$@" >/tmp/deploy-minimo-check.out 2>/tmp/deploy-minimo-check.err
  local code=$?
  set -e
  if [[ "$code" -ne 2 ]]; then
    echo "esperava recusa (2) em: $name, saiu $code" >&2
    cat /tmp/deploy-minimo-check.err >&2
    exit 1
  fi
}

expect_code() {
  local name="$1"
  local want="$2"
  shift 2
  set +e
  "$@" >/tmp/deploy-minimo-check.out 2>/tmp/deploy-minimo-check.err
  local code=$?
  set -e
  if [[ "$code" -ne "$want" ]]; then
    echo "esperava $want em: $name, saiu $code" >&2
    cat /tmp/deploy-minimo-check.err >&2
    exit 1
  fi
}

expect_reject "path curto" env DEPLOY_HOST=exemplo.com DEPLOY_USER=deploy DEPLOY_PATH=/var/www "$deploy"
expect_reject "raiz" env DEPLOY_HOST=exemplo.com DEPLOY_USER=deploy DEPLOY_PATH=/ "$deploy"
expect_reject "host" env DEPLOY_HOST='ruim host' DEPLOY_USER=deploy DEPLOY_PATH=/var/www/deploy-minimo "$deploy"
expect_reject "local raiz" "$deploy" --local /
expect_reject "metacaractere" env DEPLOY_HOST=exemplo.com DEPLOY_USER=deploy DEPLOY_PATH='/var/www/deploy;rm' "$deploy"

dry_base="$(mktemp -d)/ainda-nao"
"$deploy" --local "$dry_base" --dry-run
if [[ -e "$dry_base" ]]; then
  echo "dry-run criou o destino" >&2
  exit 1
fi

base="$(mktemp -d)"
"$deploy" --local "$base"
diff -rq "${ROOT}/site" "${base}/current"
if [[ ! -L "${base}/current" ]]; then
  echo "current não é symlink" >&2
  exit 1
fi

printf 'velho\n' >"${base}/current/sobra.txt"
"$deploy" --local "$base"
if [[ -e "${base}/current/sobra.txt" ]]; then
  echo "o release novo ainda tem sobra.txt" >&2
  exit 1
fi
if ! find "${base}/releases" -name sobra.txt | grep -q sobra.txt; then
  echo "o release anterior perdeu sobra.txt" >&2
  exit 1
fi
diff -rq "${ROOT}/site" "${base}/current"

kept="$(find "${base}/releases" -mindepth 1 -maxdepth 1 -type d | wc -l)"
if [[ "$kept" -ne 2 ]]; then
  echo "esperava 2 releases, achei $kept" >&2
  exit 1
fi

roll="$(mktemp -d)"
mkdir -p "${roll}/releases/20200101000000-1"
printf 'old\n' >"${roll}/releases/20200101000000-1/index.html"
ln -s "releases/20200101000000-1" "${roll}/current"
mkdir -p "${roll}/releases/20260101000000-2"
printf 'new\n' >"${roll}/releases/20260101000000-2/index.html"
dump="$(mktemp)"
printf '    root %s;\n' "${roll}/current" >"$dump"

expect_code "reload falha e volta" 1 \
  env ACTIVATE_NGINX_DUMP="$dump" ACTIVATE_RELOAD_CMD='exit 1' \
  bash "$activate" "$roll" "20260101000000-2" 1
if [[ "$(readlink "${roll}/current")" != "releases/20200101000000-1" ]]; then
  echo "symlink não voltou: $(readlink "${roll}/current")" >&2
  exit 1
fi
if [[ "$(cat "${roll}/current/index.html")" != "old" ]]; then
  echo "current não serve o release anterior" >&2
  exit 1
fi

printf '    root /var/www/outro/current;\n' >"$dump"
expect_code "root diferente não troca" 3 \
  env ACTIVATE_NGINX_DUMP="$dump" ACTIVATE_RELOAD_CMD='exit 0' \
  bash "$activate" "$roll" "20260101000000-2" 1
if [[ "$(readlink "${roll}/current")" != "releases/20200101000000-1" ]]; then
  echo "root errado trocou o symlink" >&2
  exit 1
fi

printf '    root %s;\n' "${roll}/current" >"$dump"
env ACTIVATE_NGINX_DUMP="$dump" ACTIVATE_RELOAD_CMD='exit 0' \
  bash "$activate" "$roll" "20260101000000-2" 1
if [[ "$(cat "${roll}/current/index.html")" != "new" ]]; then
  echo "reload ok não ativou o release novo" >&2
  exit 1
fi

prune="$(mktemp -d)"
mkdir -p "$prune/releases"
for n in 1 2 3 4 5 6; do
  mkdir -p "$(printf '%s/releases/2020010100000%s-1' "$prune" "$n")"
done
mkdir -p "${prune}/releases/20260102000000-9"
printf 'keep\n' >"${prune}/releases/20260102000000-9/ok.txt"
ln -s "releases/20200101000001-1" "${prune}/current"
bash "$activate" "$prune" "20260102000000-9" 0
left="$(find "${prune}/releases" -mindepth 1 -maxdepth 1 -type d | wc -l)"
if [[ "$left" -ne 5 ]]; then
  echo "esperava 5 releases depois da poda, achei $left" >&2
  exit 1
fi
if [[ ! -f "${prune}/current/ok.txt" ]]; then
  echo "a poda apagou o release ativo" >&2
  exit 1
fi

grep -q "root /var/www/deploy-minimo/current;" "${ROOT}/nginx/default.conf"
grep -q "listen 443 ssl;" "${ROOT}/nginx/tls.conf"
grep -q "root /var/www/deploy-minimo/current;" "${ROOT}/nginx/tls.conf"
grep -F -q 'return 301 https://$host$request_uri;' "${ROOT}/nginx/tls.conf"
if grep -q "BEGIN PRIVATE KEY" "${ROOT}/nginx/tls.conf"; then
  echo "tls.conf não pode carregar chave privada" >&2
  exit 1
fi

if command -v nginx >/dev/null; then
  tmp="$(mktemp -d)"
  sed 's/listen 80;/listen 127.0.0.1:8088;/' "${ROOT}/nginx/default.conf" >"${tmp}/server.conf"
  cat >"${tmp}/nginx.conf" <<EOF
worker_processes 1;
error_log ${tmp}/error.log;
pid ${tmp}/nginx.pid;
events { worker_connections 64; }
http {
    include /etc/nginx/mime.types;
    access_log ${tmp}/access.log;
    include ${tmp}/server.conf;
}
EOF
  nginx -t -c "${tmp}/nginx.conf"
fi
