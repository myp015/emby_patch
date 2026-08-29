# syntax=docker/dockerfile:1
# ============================================================
# Emby 官方镜像 + 自动破解/增强（复刻 amilys 完整方案）
#
# 关键设计（三大触发链，全部与 amilys 一致）:
#   1) index.html: 构建期从 base 提取 + 动态注入（HtmlPatcher v3）:
#      - emby-crx 5 引用 → head 内
#      - require.js(data-main="ext") → body 内 apploader.js 之后（顺序正确！）
#   2) ext.sh 触发: /etc/services.d/emby-server/run 每次启动:
#      首次 cp /etc/ext.sh → /config/config/ext.sh（用户可改，重启生效）
#      → 执行 ext.sh → sed 注入 extmod(ext.js)
#      → require.js 启动后按 extmod 动态加载扩展
#   3) regoff.sh: /etc/regoff.sh 每次启动:
#      写 /config/config/mb.lic + hosts 伪 mb3admin(199.255.98.60) + 注册配置
#   + DLL IL patch（Emby.Server.Implementations 验证URL→伪服务器 + registered=true
#     + MediaBrowser.Model IsMBSupporter→true）
#   + Emby.Web.dll 嵌入破解版 connectionmanager.js（与 amilys Web.dll 一致）
#   + 不再构建期 dotnet publish（buildx 无 NuGet 缓存会卡死）→ COPY 预编译产物
#
# 用法:
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     --build-arg EMBY_VERSION=4.9.5.0 \
#     -t kulai.ainas.cc/emby/embyserver:4.9.5.0 -t kulai.ainas.cc/emby/embyserver:latest --push .
# ============================================================

# 基础镜像版本（默认 latest；可传具体版本如 4.9.5.0）
ARG EMBY_VERSION=latest

# 首页美化皮肤：crx（默认，emby-crx 全家桶）| swiper_v2（home-swiper.js 轮播）
ARG SKIN=crx

# ---- 阶段A: 官方 base（multi-arch，buildx 按平台取）----
FROM emby/embyserver:${EMBY_VERSION} AS base

# ---- 阶段P: 运行 patch 工具（用预编译产物，不重新编译）----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS patcher
WORKDIR /work
ARG SKIN=crx
COPY patcher-bin/ ./patcher/
RUN mkdir -p ./dllin ./dllout ./jsin ./jsout ./htmlin ./htmlout ./webin ./webout

# 提取 base 的原始文件（按当前平台）—— 合并为一条 COPY 减少层数
COPY --from=base \
    /system/Emby.Server.Implementations.dll ./dllin/ \
    /system/MediaBrowser.Model.dll ./dllin/ \
    /system/Emby.Web.dll ./dllin/ \
    /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js ./jsin/ \
    /system/dashboard-ui/embypremiere/embypremiere.js ./jsin/ \
    /system/dashboard-ui/modules/common/usersettings/usersettingsbuilder.js ./jsin/ \
    /system/dashboard-ui/index.html ./htmlin/ \
    /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js ./webin/

# DLL IL patch（Emby.Server.Implementations + MediaBrowser.Model；Web 幂等保留）
RUN dotnet patcher/EmbyPatch2.dll ./dllin/Emby.Server.Implementations.dll ./dllout/Emby.Server.Implementations.dll && \
    dotnet patcher/EmbyPatch2.dll ./dllin/MediaBrowser.Model.dll ./dllout/MediaBrowser.Model.dll && \
    dotnet patcher/EmbyPatch2.dll ./dllin/Emby.Web.dll ./dllout/Emby.Web.dll
# JS patch（connectionmanager + embypremiere + usersettingsbuilder 侧边栏默认关闭）
RUN dotnet patcher/EmbyPatch2.dll js ./jsin/connectionmanager.js ./jsout/connectionmanager.js && \
    dotnet patcher/EmbyPatch2.dll js ./jsin/embypremiere.js ./jsout/embypremiere.js && \
    dotnet patcher/EmbyPatch2.dll js ./jsin/usersettingsbuilder.js ./jsout/usersettingsbuilder.js
# HTML patch（index.html 动态注入：皮肤→head，require.js→apploader 后 body）
#   skin: crx（emby-crx 全家桶）| swiper_v2（home-swiper.js）
RUN dotnet patcher/EmbyPatch2.dll html ./htmlin/index.html ./htmlout/index.html $SKIN
# Web.dll 嵌入破解 connectionmanager.js（复刻 amilys：官方40817→破解版）
RUN dotnet patcher/EmbyPatch2.dll js ./webin/connectionmanager.js ./webout/connectionmanager.js && \
    dotnet patcher/EmbyPatch2.dll webdll ./dllin/Emby.Web.dll ./webout/connectionmanager.js ./webout/Emby.Web.dll

# ---- 阶段D: 最终镜像 = base + 破解 + 增强 + amilys 触发链 ----
FROM base

# ===== 1+2+3) 破解产物（DLL + JS + index.html，均来自 patcher 阶段）=====
#    合并为一条 COPY 减少层数（DLL→/system/，JS→子目录，index.html→dashboard-ui）
COPY --from=patcher \
    /work/dllout/Emby.Server.Implementations.dll /system/Emby.Server.Implementations.dll \
    /work/dllout/MediaBrowser.Model.dll /system/MediaBrowser.Model.dll \
    /work/webout/Emby.Web.dll /system/Emby.Web.dll \
    /work/jsout/connectionmanager.js /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js \
    /work/jsout/embypremiere.js /system/dashboard-ui/embypremiere/embypremiere.js \
    /work/jsout/usersettingsbuilder.js /system/dashboard-ui/modules/common/usersettings/usersettingsbuilder.js \
    /work/htmlout/index.html /system/dashboard-ui/index.html

# ===== 4+5) 前端增强资源（本地 emby/：皮肤 + ext/require + 扩展模块）=====
#    合并为一条 COPY（emby/web 各文件 → dashboard-ui 对应位置）
COPY emby/web/emby-crx/ /system/dashboard-ui/emby-crx/
COPY emby/web/ext.js /system/dashboard-ui/ext.js
COPY emby/web/require.js /system/dashboard-ui/require.js
COPY emby/files/embyLaunchPotplayer.js /system/dashboard-ui/embyLaunchPotplayer.js
COPY emby/files/embyHappy.js /system/dashboard-ui/embyHappy.js
COPY emby/files/danmaku.min.js /system/dashboard-ui/danmaku.min.js

# ===== 6) amilys 触发链（本地 emby/config：ext.sh + regoff.sh + services.d）=====
#    合并为一条 COPY（各文件 → 对应 /etc 路径）
COPY emby/config/config/ext.sh /etc/ext.sh
COPY emby/config/regoff.sh /etc/regoff.sh
COPY emby/config/services.d/emby-server/run /etc/services.d/emby-server/run
COPY emby/config/services.d/emby-server/finish /etc/services.d/emby-server/finish
# 6d. 可执行位
RUN chmod +x /etc/ext.sh /etc/regoff.sh /etc/services.d/emby-server/run /etc/services.d/emby-server/finish