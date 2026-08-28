#!/bin/bash
# ============================================================
# emby 破解+增强 多架构构建，上传 kulai.ainas.cc/emby/embyserver
#
# 方案（版本锁定，避免替换不匹配）：
#   - 基础镜像：官方 emby/embyserver:4.9.3.0（multi-arch，只取 amd64+arm64）
#   - 破解补丁：从 amilys/embyserver(4.9.3.0 同版本) 提取的 5 个文件覆盖，
#       3 DLL（授权校验）+ 2 JS（前端注册/注册验证）→ crack/<arch>/
#   - 增强：embyLaunchPotplayer.js + 改版 index.html（注入 /</head> 前）
#   - 本机 arm64，amd64 用 buildx + qemu 跨架构构建
#   - 上传 kulai.ainas.cc/emby/embyserver:{latest}
#
# 用法（本机直接跑，构建并上传）：
#   ./build-multiarch.sh
#   自定义 tag：TAG=x ./build-multiarch.sh
#   只构建验证不上传：DRY=1 ./build-multiarch.sh
# ============================================================
set -e
cd "$(dirname "$0")"

REGISTRY="kulai.ainas.cc"
REPO="emby/embyserver"
TAG="${TAG:-latest}"
# 官方锁定版本（与 amilys 破解同版本 4.9.3.0，绝对匹配）
BASE_TAG="4.9.3.0"
FULL_TARGET="$REGISTRY/$REPO:$TAG"
AMD64_REF="$REGISTRY/$REPO:amd64"
ARM64_REF="$REGISTRY/$REPO:arm64"

echo "=========================================================="
echo "  私有库目标 : $FULL_TARGET"
echo "  基础镜像   : emby/embyserver:$BASE_TAG (官方,multi-arch)"
echo "  破解来源   : amilys 同版本 4.9.3.0 (crack/amd64 + crack/arm64)"
echo "  增强       : embyLaunchPotplayer.js + 改版 index.html"
echo "  主机架构   : $(uname -m)"
echo "=========================================================="

# ---- 0) 依赖与原料检查 ----
command -v docker >/dev/null || { echo "缺 docker"; exit 1; }
docker buildx version >/dev/null 2>&1 || { echo "缺 buildx"; exit 1; }
[ -f files/embyLaunchPotplayer.js ] || { echo "缺 files/embyLaunchPotplayer.js"; exit 1; }
[ -f crack/amd64/Emby.Server.Implementations.dll ] || { echo "缺 crack/amd64 破解文件"; exit 1; }
[ -f crack/arm64/Emby.Server.Implementations.dll ] || { echo "缺 crack/arm64 破解文件"; exit 1; }

# ---- 1) 确保改版 index.html 已生成（含 potplayer 引用）----
if [ ! -f index.html ] || ! grep -q "embyLaunchPotplayer" index.html; then
  echo ">>> 生成改版 index.html ..."
  if [ ! -f index.html ]; then
    echo "!! 缺原始 index.html（应来自官方 emby/embyserver:$BASE_TAG 的 amd64 变体）"
    echo "   先手动提取: docker create --platform linux/amd64 emby/embyserver:$BASE_TAG"
    echo "   然后:       docker cp <cid>:/system/dashboard-ui/index.html ./index.html"
    exit 1
  fi
  sed -i 's|</head>|<script src="embyLaunchPotplayer.js"></script>\n</head>|i' index.html
  if ! grep -q "embyLaunchPotplayer" index.html; then
    perl -i -pe 's|</head>|<script src="embyLaunchPotplayer.js"></script>\n</head>|i' index.html
  fi
  grep -q "embyLaunchPotplayer" index.html && echo "  已注入 potplayer 引用" \
    || { echo "!! 未找到 </head> 锚点"; exit 1; }
else
  echo "  index.html 已含引用，跳过注入"
fi

# ---- 2) 初始化 buildx 跨架构实例 ----
BUILDER=emby-multi
if ! docker buildx ls 2>/dev/null | grep -qw "$BUILDER"; then
  docker buildx create --name "$BUILDER" --driver docker-container --use >/dev/null 2>&1 \
    || docker buildx create --name "$BUILDER" --use >/dev/null 2>&1
else
  docker buildx use "$BUILDER"
fi

# ---- 3) 分别构建并推送 amd64 / arm64 补丁版（锁定官方 4.9.3.0 基础）----
echo ">>> 构建并推送 amd64 -> $AMD64_REF ..."
docker buildx build --platform linux/amd64 \
  --provenance=false \
  -t "$AMD64_REF" -f Dockerfile.amd64 --push \
  --build-arg BASE_TAG="$BASE_TAG" . \
  || { echo "!! amd64 失败（跨架构需 qemu：docker run --rm --privileged multiarch/qemu-user-static --reset -p yes）"; exit 1; }

echo ">>> 构建并推送 arm64 -> $ARM64_REF ..."
docker buildx build --platform linux/arm64 \
  --provenance=false \
  -t "$ARM64_REF" -f Dockerfile.arm64 --push \
  --build-arg BASE_TAG="$BASE_TAG" . \
  || exit 1

# ---- 4) 合成 multi-arch manifest ----
echo ">>> 合成 multi-arch -> $FULL_TARGET ..."
docker manifest rm "$FULL_TARGET" 2>/dev/null || true
docker manifest create "$FULL_TARGET" "$AMD64_REF" "$ARM64_REF"
docker manifest annotate "$FULL_TARGET" "$AMD64_REF" --os linux --arch amd64
docker manifest annotate "$FULL_TARGET" "$ARM64_REF" --os linux --arch arm64

if [ "$DRY" = "1" ]; then
  echo "!!! DRY=1：已合成但未推送。查看: docker manifest inspect $FULL_TARGET"
  echo "    推送: docker manifest push $FULL_TARGET"
else
  echo ">>> 推送 multi-arch -> $FULL_TARGET ..."
  docker manifest push "$FULL_TARGET"
fi

echo ""
echo "=========================================================="
echo "✅ 完成：$FULL_TARGET"
echo "   官方 emby/embyserver:$BASE_TAG 基础 + amilys 破解 + potplayer 增强"
echo "   验证: docker manifest inspect $FULL_TARGET"
echo "   部署: docker pull $FULL_TARGET"
echo "=========================================================="