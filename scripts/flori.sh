#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source $ROOT_DIR/scripts/base.sh



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

_pool_run(){
  local pool=${1:-}
  if [[ -z "$pool" ]]; then
    echo "缺少 pool"
    return 1
  fi
  
  local env_file="$(find . -path "*${pool}/pool.env")"
  local DC=(
    "sudo" "docker" "compose"
    "-p" "${pool}"
    "--env-file" "$env_file"
    "-f" "frappe_docker/compose.yaml" 
    "-f" "frappe_docker/overrides/compose.mariadb.yaml" 
    "-f" "compose/compose.mariadb.healthcheck.yml"
    "-f" "frappe_docker/overrides/compose.redis.yaml" 
    "-f" "frappe_docker/overrides/compose.noproxy.yaml" 
    "-f" "compose/compose.noproxy.traefik.yml" 
  )
  shift
  ${DC[@]} $@
}


domain(){
  # flori domain [domain]  :操作domain 默认创建domain

  _permission "node"

  local domain=$1

  local env_file="$(find . -path "*${domain}/domain.env")"
  local pool=$(_get_env $env_file "POOL_NAME")
  local default_site_name=$(_get_env $env_file "DEFAULT_SITE_NAME")
  local domian=$(_get_env $env_file "DOMAIN")


  _pool_run $pool exec backend bench setup add-domain "$domian" --site "$default_site_name"
  _pool_run $pool exec backend ln -s "/home/frappe/frappe-bench/sites/$default_site_name" "/home/frappe/frappe-bench/sites/$domian"
 

  hosts=""
  for file in $(find -path "*${default_site_name//.dev.lan/}/*/domain.env"); do
    value=$(_get_env $file "TRAEFIK_HOST")
 
   if [ -z "$hosts" ]; then
      hosts="$value"
    else
      hosts="$hosts \|\| $value"
    fi
  done
  local pool_env_file="$(find . -path "*${pool}/pool.env")"

  sed -i "s#^TRAEFIK_HOSTS=.*#TRAEFIK_HOSTS=${hosts}#" "$pool_env_file"
  _pool_run $pool  restart frontend backend
}

site() {
  # flori site [site] :操作site 默认创建site
  
  _permission "node"
  
  local site=$1
  local env_file="$(find . -path "*${site}/site.env")"
  source "$env_file"
  local pool=$POOL_NAME

  _pool_run $pool exec backend bench new-site "$DEFAULT_SITE_NAME" \
    --mariadb-user-host-login-scope='%' \
    --db-root-username "$DB_ROOT_USERNAME" \
    --db-root-password "$DB_ROOT_PASSWORD" \
    --admin-password "$ADMIN_PASSWORD" \
    --install-app "$INSTALL_APP"
  _pool_run $pool exec backend bench use "$DEFAULT_SITE_NAME"
  _pool_run $pool exec backend bench config dns_multitenant on
  _pool_run $pool restart 
}



pool() {
  # flori pool [pool] :操作pool
  
  _permission "node"
  _pool_run $@
  
}

build() {
  # flori build [app] [branch] :构建 app 镜像 
  _permission "node"
  local app=${1:-}
  local branch=${2:-}

  if [[ -z "$app" ||  -z "$branch" ]]; then
    echo "缺少 app branch"
    return 1
  fi

  local env_file="$(find . -path "*${app}/${branch}/app.env")"
  sudo docker compose \
    --env-file "$env_file" \
    -f compose/compose.images.yml \
    build build-image
}

gate(){
  # flori gate :初始化traefik
  _permission "node"
  sudo docker network inspect traefik-public 2>/dev/null 1>/dev/null
  if [ $? -ne 0 ];then
    sudo docker network create traefik-public 
  fi
  
  sudo docker compose --env-file "env/traefik.env" \
    -f "compose/compose.traefik.yml" $@
}

rand() {
  # flori rand [n] :产生随机字符串 
  tr -dc '0-9a-z' < /dev/urandom | head -c $1
}

create() {
  # flori create  :创建配置文件 [app] [branch] [pool] [site] [domain]

  local app="${1:-}"
  local branch="${2:-}"
  local pool="${3:-}"
  local site="${4:-}"
  local domain="${5:-}"

  _create_branch $app $branch
  _create_pool $app $branch $pool
  _create_site $app $branch $pool $site
  _create_domain $app $branch $pool $site $domain
}

test(){
  # flori test :测试
  echo "test"
}

"$@"
