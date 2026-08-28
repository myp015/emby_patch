#!/bin/bash
# 本机发布 EmbyPatch2（含 Mono.Cecil），产物放项目 patcher-bin/，Dockerfile 直接 COPY 跳过构建期 publish
export PATH="$PATH:/root/.dotnet"
cd /www/project/emby_patch
echo "=== 本机发布 patch2 -> patcher-bin/ ==="
rm -rf patcher-bin
dotnet publish patch2 -c Release -o patcher-bin --nologo 2>&1 | tail -3
echo ""
echo "=== 产物确认 ==="
ls -la patcher-bin/ | grep -E "EmbyPatch2|Mono.Cecil" | head
echo ""
echo "=== 关键文件 ==="
[ -f patcher-bin/EmbyPatch2.dll ] && echo "✅ EmbyPatch2.dll 存在 ($(stat -c%s patcher-bin/EmbyPatch2.dll) bytes)" || echo "❌ 缺失"
[ -f patcher-bin/Mono.Cecil.dll ] && echo "✅ Mono.Cecil.dll 存在" || echo "❌ 缺失"
[ -f patcher-bin/EmbyPatch2.runtimeconfig.json ] && echo "✅ runtimeconfig 存在" || echo "❌ 缺失"