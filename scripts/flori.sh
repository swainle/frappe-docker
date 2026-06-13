#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

init(){
  # flori init [owner] :owner 可选 [master|node|register] 
  
  [ -f "/usr/local/bin/flori" ] && sudo rm /usr/local/bin/flori
  sudo ln -s $(pwd)/scripts/flori.sh /usr/local/bin/flori
  git submodule update --init --recursive
  echo "$1" > $ROOT_DIR/owner.txt
}

help() {
  # flori help :帮助列表

  local src="${BASH_SOURCE[0]}"
  local funcs

  funcs="$(declare -F | awk '{print $3}' | tr '\n' ' ')"

  echo "Flori Docker 工具, 用于管理frappe镜像的构建, 运行, 备份, 迁移"
  echo "-----------------------------"

  awk -v funcs="$funcs" '
    BEGIN {
      n = split(funcs, f, " ")
      for (i = 1; i <= n; i++) {
        if (f[i] != "") exists[f[i]] = 1
      }
    }

    /^[[:space:]]*#[[:space:]]*flori[[:space:]]+/ {
      line = $0

      sub(/^[[:space:]]*#[[:space:]]*/, "# ", line)
      gsub(/[[:space:]]+$/, "", line)

      usage = line
      desc = ""

      if (match(line, /[[:space:]]+:[[:space:]]*/)) {
        usage = substr(line, 1, RSTART - 1)
        desc = substr(line, RSTART + RLENGTH)
      }

      cmd_text = usage
      sub(/^#[[:space:]]*flori[[:space:]]+/, "", cmd_text)
      split(cmd_text, parts, /[[:space:]]+/)
      cmd = parts[1]

      if (cmd == "") next
      if (cmd ~ /^_/) next
      if (!(cmd in exists)) next

      printf "%s\t%06d\t%s\t%s\n", cmd, ++seq[cmd], usage, desc
    }
  ' "$src" |
  sort -t $'\t' -k1,1 -k2,2n |
  awk -F '\t' '
    {
      cmd[NR] = $1
      usage[NR] = $3
      desc[NR] = $4

      if (length($1) > width) width = length($1)
    }

    END {
      if (width < 7) width = 7

      prev = ""

      for (i = 1; i <= NR; i++) {
        if (cmd[i] == prev) {
          printf "%-*s  %-32s %s\n", width, "", usage[i], desc[i]
        } else {
          printf "%-*s  %-32s %s\n", width, cmd[i], usage[i], desc[i]
        }

        prev = cmd[i]
      }
    }
  '
}

exec(){
  # flori exec [command] :执行docker compose [command]
  _permission "node"
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
  # flori site [site] :使用容器创建site
  
  _permission "node"
  
  NAME=$(basename $1)
  ENV_FILE="sites/${NAME}"
  . $ENV_FILE

  exec $1 up -d
  exec $1 exec backend bench new-site "$SITE_NAME" \
    --mariadb-user-host-login-scope='%' \
    --db-root-username "$DB_ROOT_USERNAME" \
    --db-root-password "$DB_ROOT_PASSWORD" \
    --admin-password "$ADMIN_PASSWORD" \
    --install-app "$INSTALL_APP"
  exec $1 exec backend bench use "$SITE_NAME"
  exec $1 exec backend bench config dns_multitenant on
  exec $1 restart 
}

build() {
  # flori build [app] :构建 app 镜像
  
  _permission "node"
  
  sudo docker compose \
    --env-file "$1" \
    -f compose/compose.images.yml \
    build build-image
}

_permission(){
  if [ ! -f "$ROOT_DIR/owner.txt" ];then
    echo "$ROOT_DIR/owner.txt 文件未创建"
    exit 1
  fi
  OWNER="$(awk 'NF { print; exit }' $ROOT_DIR/owner.txt)"
  if  [[ "$OWNER" != *"$1"* ]]; then
    echo "$1 没权限使用"
    exit 1
  fi
}

test(){
  # flori test :测试
  echo "test"
}

"$@"