#!/bin/sh

######## 说明（复刻 amilys /etc/ext.sh，默认启用扩展） ########
# 容器每次启动时运行（由 /etc/services.d/emby-server/run 触发）
# 作用：
#   1) 注入 MediaId 到 emby-crx/config.js（媒体库美化范围，留空=全部）
#   2) 注入 extmod 数组到 ext.js（require.js 动态加载哪些扩展模块）
#      ★ 默认启用三个模块（开箱即用，与 amilys 需手动改不同）
############################################################

echo "Emby 扩展启动脚本"

# 去掉下行注释可以关闭本脚本
#exit 0

######## 下面可以自行添加功能 ########

## 修改容器 hosts（可选示例）
#echo -e "13.226.210.20     api.themoviedb.org" >> /etc/hosts
#echo -e "13.225.142.99     api4.thetvdb.com" >> /etc/hosts

## emby-crx 美化：媒体库 ID（进入媒体库后 URL 里的 parentId，逗号分隔；留空=全部媒体库）
MediaId=""

## 扩展模块（require.js 动态加载，★默认全部启用）:
#   embyLaunchPotplayer 外部播放器（老板指定源，异步加载→播放按钮之后）
#   ede.user 弹幕
#   actorPlus 隐藏未知演员
extmod='["embyLaunchPotplayer","ede.user","actorPlus"]'

# 注入 MediaId 到 emby-crx/config.js（this.parentId）
sed -i '/this.parentId/s/""\|"[0-9]\+"\|"\([0-9]\+,\)\+[0-9]\+"/"'"$MediaId"'"/g' /system/dashboard-ui/emby-crx/config.js

# 注入 extmod 到 ext.js（require.js 按此加载扩展模块 → 插件生效）
sed -i '/\ extmod/s/\[.*\]/'"$extmod"'/g' /system/dashboard-ui/ext.js

exit 0