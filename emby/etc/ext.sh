#!/bin/sh

######## 说明 2023-07-30 ########
#一个sh脚本，容器每次启动时运行
#方便自定义添加功能
#################################


echo "Emby扩展启动脚本"

#去掉下行注释可以关闭次脚本
#exit 0

########下面可以自行添加功能########

## 修改容器hosts

#echo -e "13.226.210.20     api.themoviedb.org" >> /etc/hosts
#echo -e "13.225.142.99     api4.thetvdb.com" >> /etc/hosts

## 首页美化（皮肤由 index.html 注入，无需在此处理）
##   - crx      : emby-crx 全家桶（style.css + common-utils/jquery/md5/config/main.js）
##   - swiper_v2: home-swiper.js 首页轮播（单文件，自带 Swiper CSS）

## 扩展模块（ext.js 由 require.js 加载，extmod 控制加载哪些）
# embyLaunchPotplayer 外部播放（index.html 直接引用，不走 extmod）
#extmod='["embyLaunchPotplayer"]'

extmod='[]'
sed -i '/\ extmod/s/\[.*\]/'$extmod'/g' /system/dashboard-ui/ext.js

exit 0
