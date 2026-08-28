#!/bin/bash
# 安装 .NET 8 SDK（arm64/Debian13）用 dotnet-install 脚本，验证 patch 工具用
set -e
ARCH=$(uname -m)
echo "=== 安装 .NET 8 SDK (arch=$ARCH) ==="
curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh
# 安装到 /root/.dotnet
/tmp/dotnet-install.sh --channel 8.0 --install-dir /root/.dotnet --no-path 2>&1 | tail -5
# 加 PATH
export PATH="$PATH:/root/.dotnet"
echo ""
echo "=== 验证 ==="
dotnet --version
echo "=== 准备 NuGet 源（Mono.Cecil）==="
mkdir -p /root/.nuget/NuGet
echo "=== dotnet 就绪 ==="