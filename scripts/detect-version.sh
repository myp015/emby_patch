#!/bin/bash
# ============================================================
# 探测官方 emby/embyserver:latest 对应的版本号（digest 匹配）
# 用法:
#   scripts/detect-version.sh            # 只输出版本号
#   scripts/detect-version.sh latest     # 输入官方 tag，输出版本号
# 原理: 查 Docker Hub tag 列表，找 digest 与 latest 相同的非 latest tag
# ============================================================
set -e

INPUT_TAG="${1:-latest}"

if [ "$INPUT_TAG" != "latest" ]; then
  # 手动指定版本，直接用
  echo "$INPUT_TAG"
  exit 0
fi

LATEST_DIGEST=$(curl -s "https://hub.docker.com/v2/repositories/emby/embyserver/tags/latest" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['digest'])" 2>/dev/null || true)

if [ -z "$LATEST_DIGEST" ]; then
  echo "latest"   # 无法访问 API，回退 latest
  exit 0
fi

# 在 tag 列表里找 digest 匹配的版本号（单行 python，避免 YAML/多行问题）
DETECTED=$(curl -s "https://hub.docker.com/v2/repositories/emby/embyserver/tags?page_size=100" \
  | python3 -c "
import sys,json
t='$LATEST_DIGEST'
for r in json.load(sys.stdin).get('results',[]):
    n=r['name']
    if ':' not in n and r.get('digest','')==t and n!='latest':
        print(n); break
" 2>/dev/null || true)

[ -n "$DETECTED" ] && echo "$DETECTED" || echo "latest"
