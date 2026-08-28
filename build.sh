#!/bin/bash
# ============================================================
# emby 破解镜像构建 + 上传 kulai.ainas.cc/emby/embyserver
# 基础: 官方 emby/embyserver:latest (multi-arch)
# 破解: 构建期自动 patch（DLL IL + JS），复刻 amilys 方案
# 用法:
#   ./build.sh            # 构建 arm64 本地验证（不上传）
#   ./build.sh --push     # 构建 amd64+arm64 multi-arch 并上传
#   TAG=x ./build.sh --push  # 自定义 tag
# ============================================================
set -e
cd "$(dirname "$0")"

REGISTRY="kulai.ainas.cc"
REPO="emby/embyserver"
TAG="${TAG:-latest}"
FULL_TARGET="$REGISTRY/$REPO:$TAG"

echo "=========================================================="
echo "  目标: $FULL_TARGET"
echo "  基础: emby/embyserver:latest (官方 multi-arch)"
echo "  破解: 构建期自动 patch（DLL+JS，复刻 amilys）"
echo "  增强: embyLaunchPotplayer + 改版 index.html"
echo "=========================================================="

# 0) 依赖检查
command -v docker >/dev/null || { echo "缺 docker"; exit 1; }
docker buildx version >/dev/null 2>&1 || { echo "缺 buildx"; exit 1; }
[ -f files/embyLaunchPotplayer.js ] || { echo "缺 files/embyLaunchPotplayer.js"; exit 1; }
[ -f index.html ] || { echo "缺 index.html"; exit 1; }

# 1) buildx 实例
BUILDER=emby-multi
if ! docker buildx ls 2>/dev/null | grep -qw "$BUILDER"; then
  docker buildx create --name "$BUILDER" --driver docker-container --use >/dev/null 2>&1 \
    || docker buildx create --name "$BUILDER" --use >/dev/null 2>&1
else
  docker buildx use "$BUILDER"
fi

if [ "$1" = "--push" ]; then
  echo ">>> 构建 amd64+arm64 并推送 $FULL_TARGET ..."
  docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --provenance=false \
    -t "$FULL_TARGET" \
    -f Dockerfile \
    --push .
  echo ""
  echo "✅ 完成: $FULL_TARGET (multi-arch)"
  echo "   验证: docker manifest inspect $FULL_TARGET"
else
  echo ">>> 构建 arm64（本地验证，不上传）..."
  docker buildx build \
    --platform linux/arm64 \
    --provenance=false \
    -t "$FULL_TARGET" \
    -f Dockerfile \
    --load .
  echo ""
  echo "✅ 本地构建完成: $FULL_TARGET"
  echo "   验证: docker run --rm $FULL_TARGET /bin/sh -c 'ls /system/*.dll | head'"
  echo "   上传: ./build.sh --push"
fi