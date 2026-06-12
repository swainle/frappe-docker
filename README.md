# Flori Docker 
本项目引用 frappe_docker 配置apps 下.env 及 .json 达到构建不同应用镜像的效果。
## 使用
首先复制 `wiki-v3.0.0-rc.4.env` 及 `wiki-v3.0.0-rc.4.json` 然后修改变量
|变量|说明|-|
|-|-|-|
|PYTHON_VERSION|python版本|注意跟开发版本一致|
|NODE_VERSION|NODEJS 版本|注意跟开发版本一致|
|DEBIAN_BASE|基础镜像版本|debian 12|
|FRAPPE_PATH|frappe仓库||
|FRAPPE_BRANCH|frappe版本||
|WKHTMLTOPDF_VERSION|WKHTMLTOPDF版本||
|WKHTMLTOPDF_DISTRO|WKHTMLTOPDF系统名称||
|INSTALL_CHROMIUM|是否安装chromium-headless-shell||
|IMAGE_REPOSITORY|构建镜像名称||
|IMAGE_TAG|构建镜像版本||
|APPS_JSON_FILE|应用配置文件|相对compose文件|

构建
```
cd flori
sudo docker compose \
  --env-file apps/wiki-v3.0.0-rc.4.env\
  -f compose/docker.images.yml \
  build build-image
```
在github获取有package权限的TOKEN PAT
```shell
echo <PAT> | docker login ghcr.io -u swainle --password-stdin
```
打标签
```shell
sudo docker tag flori:wiki-v3.0.0-rc.4 ghcr.io/swainle/flori:wiki-v3.0.0-rc.4
```
推送
```shell
 sudo docker push ghcr.io/swainle/flori:wiki-v3.0.0-rc.4
```
创建站点
```
./dc.sh bench new-site wiki.flori.lan   --mariadb-user-host-login-scope='%'   --db-root-password 123 --db-root-username root   --admin-password 123   --install-app wiki
允许多用户
./dc.sh bench config dns_multitenant on 
```