#!/bin/sh

######## 说明 ########
# 容器每次启动时运行（复刻 amilys 模式）
# 作用：通过 sed 修改 /system/dashboard-ui/ext.js 里的 extmod 配置数组，
#       动态加载 embyLaunchPotplayer / ede.user 弹幕 / actorPlus 等扩展模块。
#       模块由 require.js 异步加载（页面渲染后执行）→ 外部播放器按钮正确插到播放按钮之后。
################################

echo "Emby 扩展启动脚本"

# 去掉下行注释可以关闭本脚本
#exit 0

######## 下面可以自行添加功能 ########

## 媒体库ID（emby-crx 美化作用范围，进入媒体库后地址栏 parentId，逗号分隔）
MediaId=""

## 扩展模块（require.js 动态加载）：
# embyLaunchPotplayer 外部播放器
# ede.user 弹幕
# actorPlus 未知演员隐藏
extmod='["embyLaunchPotplayer","ede.user","actorPlus"]'

# 注入 extmod 到 ext.js（embyLaunchPotplayer 在播放页渲染后加载 → 播放按钮之后）
sed -i "/extmod/s/\[.*\]/$extmod/g" /system/dashboard-ui/ext.js

# （可选）MediaId 注入 emby-crx config
if [ -n "$MediaId" ]; then
  sed -i "s/this.parentId = \"\"/this.parentId = \"$MediaId\"/g" /system/dashboard-ui/emby-crx/config.js 2>/dev/null
fi

exit 0