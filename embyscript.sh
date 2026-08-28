#!/bin/bash

name="emby-8096"
echo "emby 页面美化安装中..."

# 判断容器是否运行
if ! docker ps --format '{{.Names}}' | grep -wq "$name"; then
    echo -e "\033[0;31m错误: 容器 $name 未运行，退出脚本。\033[0m"
    exit 1
fi

# 下载 JS 文件
url="http://47.103.159.168:8008/urlbash/embyscript/embyLaunchPotplayer.sh"
wget -q --no-check-certificate "$url" -O embyLaunchPotplayer.js
docker cp embyLaunchPotplayer.js "$name":/system/dashboard-ui/
rm -f embyLaunchPotplayer.js

# 拉出 index.html
docker cp "$name":/system/dashboard-ui/index.html ./index.html

# 检查是否已安装脚本
if grep -q "embyLaunchPotplayer" index.html; then
    echo -e "\033[0;34m脚本已存在，跳过插入。\033[0m"  # 蓝色
else
    # 插入脚本引用
    sed -i '/<script src="apploader.js" defer><\/script>/a\<script src="embyLaunchPotplayer.js"></script>' index.html
    echo -e "\033[0;32m脚本已成功插入 index.html。\033[0m"  # 绿色
fi

# 备份原文件
docker exec "$name" mkdir -p /system/dashboard-ui/bak/
docker cp ./index.html "$name":/system/dashboard-ui/bak/index.html

# 更新容器内文件
docker cp ./index.html "$name":/system/dashboard-ui/index.html

# 清理本地
rm -f index.html

echo -e "\033[0;32memby 页面美化已完成！\033[0m"
