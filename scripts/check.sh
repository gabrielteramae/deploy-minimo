#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
deploy="${ROOT}/scripts/deploy.sh"

bash -n "$deploy"

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

expect_reject "path curto" env DEPLOY_HOST=exemplo.com DEPLOY_USER=deploy DEPLOY_PATH=/var/www "$deploy"
expect_reject "raiz" env DEPLOY_HOST=exemplo.com DEPLOY_USER=deploy DEPLOY_PATH=/ "$deploy"
expect_reject "host" env DEPLOY_HOST='ruim host' DEPLOY_USER=deploy DEPLOY_PATH=/var/www/deploy-minimo "$deploy"
expect_reject "local raiz" "$deploy" --local /

dest="$(mktemp -d)"
printf 'velho\n' >"${dest}/sobra.txt"
"$deploy" --local "$dest"
diff -rq "${ROOT}/site" "$dest"
if [[ -e "${dest}/sobra.txt" ]]; then
  echo "--delete não removeu sobra.txt" >&2
  exit 1
fi

if command -v nginx >/dev/null; then
  tmp="$(mktemp -d)"
  cat >"${tmp}/nginx.conf" <<EOF
worker_processes 1;
error_log ${tmp}/error.log;
pid ${tmp}/nginx.pid;
events { worker_connections 64; }
http {
    include /etc/nginx/mime.types;
    access_log ${tmp}/access.log;
    include ${ROOT}/nginx/default.conf;
}
EOF
  nginx -t -c "${tmp}/nginx.conf"
fi
