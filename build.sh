#!/bin/bash
# ============================================================
# emby 增强镜像构建 + 上传私有库
# 基础: 官方 emby/embyserver (multi-arch)
# 破解: 构建期自动 patch（DLL IL + JS + 前端注入 v3）
# 增强: embyHappy + embyLaunchPotplayer + swiper_v2轮播 + regoff 触发链
#
# 用法:
#   ./build.sh                      # 构建 arm64 本地验证（不上传）
#   ./build.sh --push               # 构建 amd64+arm64 上传 latest + 版本号
#   EMBY_VERSION=4.9.5.0 ./build.sh --push   # 指定官方基础版本
#   TAG=4.9.5.0 ./build.sh          # 自定义输出 tag（默认 = 探测的版本号）
#   REGISTRY=docker.ainas.cc:5200 ./build.sh --push  # 指定推送库（默认 kulai.ainas.cc）
#
# 版本策略:
#   - 不传 EMBY_VERSION: 用官方 latest，并自动探测其对应版本号（digest 匹配）
#   - 传了 EMBY_VERSION: 用指定官方版本
#   - --push 时同时推送 <版本号> 和 latest 两个 tag
# ============================================================
set -e
cd "$(dirname "$0")"

REGISTRY="${REGISTRY:-kulai.ainas.cc}"
REPO="emby/embyserver"
EMBY_VERSION="${EMBY_VERSION:-latest}"
TAG="${TAG:-$EMBY_VERSION}"

echo "=========================================================="
echo "  官方基础: emby/embyserver:$EMBY_VERSION"
echo "  破解: 构建期自动 patch（DLL IL + JS + HTML v3 + webdll）"
echo "  触发: regoff.sh 写 mb.lic + 前端增强直接嵌入 index.html"
echo "=========================================================="

# 0) 依赖检查
command -v docker >/dev/null || { echo "缺 docker"; exit 1; }
docker buildx version >/dev/null 2>&1 || { echo "缺 buildx"; exit 1; }
[ -f emby/files/embyLaunchPotplayer.js ] || { echo "缺 emby/files/embyLaunchPotplayer.js"; exit 1; }
[ -d patcher-bin ] || { echo "缺 patcher-bin（先跑 tools/emby-patch2 发布）"; exit 1; }

# 1) 若用 latest，自动探测版本号（digest 匹配官方 tag 列表）
if [ "$EMBY_VERSION" = "latest" ]; then
  echo ">>> 探测官方 latest 对应的版本号..."
  LATEST_DIGEST=$(curl -s "https://hub.docker.com/v2/repositories/emby/embyserver/tags/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['digest'])" 2>/dev/null || true)
  if [ -n "$LATEST_DIGEST" ]; then
    DETECTED=$(curl -s "https://hub.docker.com/v2/repositories/emby/embyserver/tags?page_size=100" \
      | python3 -c "
import sys, json
d = json.load(sys.stdin)
t = '$LATEST_DIGEST'
for r in d.get('results', []):
    n = r['name']
    if ':' not in n and r.get('digest','') == t and n != 'latest':
        print(n); break
" 2>/dev/null || true)
    if [ -n "$DETECTED" ]; then
      TAG="$DETECTED"
      echo "    ✅ latest -> 版本号 $TAG (digest $LATEST_DIGEST)"
    else
      echo "    ⚠️ 未匹配到版本号 tag，使用 latest"
    fi
  else
    echo "    ⚠️ 无法访问 Docker Hub API，使用 latest"
  fi
fi

FULL_TARGET="$REGISTRY/$REPO:$TAG"
echo "  输出 tag: $TAG"

# 2) buildx 实例
BUILDER=emby-multi
if ! docker buildx ls 2>/dev/null | grep -qw "$BUILDER"; then
  docker buildx create --name "$BUILDER" --driver docker-container --use >/dev/null 2>&1 \
    || docker buildx create --name "$BUILDER" --use >/dev/null 2>&1
else
  docker buildx use "$BUILDER"
fi

if [ "$1" = "--push" ]; then
  # 3) 推送：版本号 tag + latest tag
  TAGS="-t $FULL_TARGET"
  if [ "$TAG" != "latest" ]; then
    TAGS="$TAGS -t $REGISTRY/$REPO:latest"
  fi
  echo ">>> 构建 amd64+arm64 并推送: $TAGS ..."
  docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --build-arg EMBY_VERSION="$EMBY_VERSION" \
    --provenance=false \
    $TAGS \
    -f Dockerfile \
    --push .
  echo ""
  echo "✅ 完成: $TAGS (multi-arch)"
  echo "   验证: docker manifest inspect $REGISTRY/$REPO:$TAG"
else
  echo ">>> 构建 arm64（本地验证，不上传）..."
  docker buildx build \
    --platform linux/arm64 \
    --build-arg EMBY_VERSION="$EMBY_VERSION" \
    --provenance=false \
    -t "$FULL_TARGET" \
    -f Dockerfile \
    --load .
  echo ""
  echo "✅ 本地构建完成: $FULL_TARGET"
  echo "   验证: docker run --rm $FULL_TARGET /bin/sh -c 'ls /system/*.dll | head'"
  echo "   上传: ./build.sh --push"
fi