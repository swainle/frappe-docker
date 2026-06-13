#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

init(){
  # flori init :初始化程序 安装:子模块 可执行程序
  [ -f "/usr/local/bin/flori" ] && sudo rm /usr/local/bin/flori
  sudo ln -s $(pwd)/scripts/flori.sh /usr/local/bin/flori
  git submodule update --init --recursive
}

help() {
  # flori help :帮助列表

  local show_all=0
  [[ "${1:-}" == "-a" || "${1:-}" == "--all" ]] && show_all=1

  local src="${BASH_SOURCE[0]}"
  local funcs

  funcs="$(declare -F | awk '{print $3}' | tr '\n' ' ')"

  echo "Flori Docker 工具, 用于管理frappe镜像的构建, 运行, 备份, 迁移"
  echo "-----------------------------"

  awk -v funcs="$funcs" -v show_all="$show_all" '
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
      if (!show_all && cmd ~ /^_/) next
      if (!show_all && !(cmd in exists)) next

      # 输出：命令名、出现顺序、用法、说明
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
  sudo docker compose \
    --env-file "$1" \
    -f compose/compose.images.yml \
    build build-image
}

"$@"