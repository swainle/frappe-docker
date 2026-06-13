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

_get_env() {
  grep "^$2=" "$1" | cut -d '=' -f2-
}

_create_branch(){
  local app="${1:-}"
  local branch="${2:-}"

  if [[ -z "$app" || -z "$branch" ]]; then
    echo "用法: create [app] [branch] [pool] [site] [domain]"
    return 1
  fi

  dir="$ROOT_DIR/env/apps/${app}/${branch}"
  if [[ -d "$dir" ]]; then
    echo "$dir 已存在"
  else
    mkdir -p "$dir" 

    cat > "$dir/app.env" <<EOF
# 按应用修改
PYTHON_VERSION=3.14.5
NODE_VERSION=24.16.0
FRAPPE_BRANCH=version-16
FRAPPE_PATH=https://github.com/frappe/frappe

# 默认版本
DEBIAN_BASE=bookworm
WKHTMLTOPDF_VERSION=0.12.6.1-3
WKHTMLTOPDF_DISTRO=bookworm
INSTALL_CHROMIUM=true

# 自动生成
IMAGE_REPOSITORY=flori
IMAGE_TAG=${app}-${branch}
APPS_JSON_FILE=../env/apps/${app}/${branch}/app.json
CACHE_BUST=${app}-${branch}-$(date +%Y%m%d)
EOF
    echo "创建 $dir/app.env"
    cat > "$dir/app.json" <<EOF
[
  {
    "url": "https://github.com/frappe/${app}",
    "branch": "${branch}"
  }
]
EOF
    echo "创建 $dir/app.json"
  fi


}

_create_pool(){
  local app="${1:-}"
  local branch="${2:-}"
  local pool="${3:-}"

  if [[ -z "$pool"  ]]; then
    echo "缺少 pool"
    return 1
  fi

  dir="$ROOT_DIR/env/apps/${app}/${branch}/${pool}"
  if [[ -d "$dir" ]]; then
    echo "$dir 已存在"
  else
    mkdir -p "$dir" 
    cat > "$dir/pool.env" <<EOF
HTTP_PUBLISH_PORT=8081

# 当前pool 都是使用这个镜像
CUSTOM_IMAGE=flori
CUSTOM_TAG=press-v0.42.10
PULL_POLICY=missing
RESTART_POLICY=unless-stopped


GUNICORN_WORKERS=1
GUNICORN_THREADS=2
GUNICORN_TIMEOUT=120

# !:程序自动修改
TRAEFIK_HOSTS=
EOF
    echo "创建 $dir/pool.env"
  fi


}

_create_site(){
  local app="${1:-}"
  local branch="${2:-}"
  local pool="${3:-}"
  local site="${4:-}"
  if [[ -z "$site"  ]]; then
    echo "缺少 site"
    return 1
  fi

  dir="$ROOT_DIR/env/apps/${app}/${branch}/${pool}/${site}"
  if [[ -d "$dir" ]]; then
    echo "$dir 已存在"
  else
    mkdir -p "$dir" 
    cat > "$dir/site.env" <<EOF
POOL_NAME=${pool}
DEFAULT_SITE_NAME=${site}.dev.lan

# 固定账号密码
INSTALL_APP=press
ADMIN_PASSWORD=123
DB_ROOT_USERNAME=root
DB_ROOT_PASSWORD=123
DB_PASSWORD=123
EOF
    echo "创建 $dir/site.env"
  fi

}

_create_domain(){
  local app="${1:-}"
  local branch="${2:-}"
  local pool="${3:-}"
  local site="${4:-}"
  local domain="${5:-}"
  if [[ -z "$domain"  ]]; then
    echo "缺少 domain"
    return 1
  fi

  dir="$ROOT_DIR/env/apps/${app}/${branch}/${pool}/${site}/${domain}"
  if [[ -d "$dir" ]]; then
    echo "$dir 已存在"
  else
    mkdir -p "$dir" 
    cat > "$dir/domain.env" <<EOF
POOL_NAME=${pool}
DEFAULT_SITE_NAME=${site}.dev.lan
DOMAIN=${domain}.a.s.dev.flori.cc
TRAEFIK_HOST=Host(\\\`${domain}.a.s.dev.flori.cc\\\`)
EOF
    echo "创建 $dir/domain.env"
  fi

}