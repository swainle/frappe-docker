#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

dock(){
  NAME=$(basename $1)
  ENV_FILE="sites/${NAME}"
  DC=(
    "sudo" "docker" "compose"
    "-p" "${NAME//./-}"
    "--env-file" "$ENV_FILE"
    "-f" "frappe_docker/compose.yaml" 
    "-f" "frappe_docker/overrides/compose.mariadb.yaml" 
    "-f" "compose/compose.mariadb.healthcheck.yml"
    "-f" "frappe_docker/overrides/compose.redis.yaml" 
    "-f" "frappe_docker/overrides/compose.noproxy.yaml" 
  )
  shift
  ${DC[@]} $@
}
site() {
  NAME=$(basename $1)
  ENV_FILE="sites/${NAME}"
  . $ENV_FILE

  dock $1 up -d
  dock $1 exec backend bench new-site "$SITE_NAME" \
    --mariadb-user-host-login-scope='%' \
    --db-root-username "$DB_ROOT_USERNAME" \
    --db-root-password "$DB_ROOT_PASSWORD" \
    --admin-password "$ADMIN_PASSWORD" \
    --install-app "$INSTALL_APP"
  dock $1 exec backend bench use "$SITE_NAME"
  dock $1 exec backend bench config dns_multitenant on
  dock $1 restart 
}

build() {
  sudo docker compose \
    --env-file "$1" \
    -f compose/compose.images.yml \
    build build-image
}


# ./dc.sh build apps/wiki-v3.0.0-rc.4
# ./dc.sh site sites/wiki.flori.lan
"$@"