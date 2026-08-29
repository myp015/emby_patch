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

# 提取 base 的原始文件（按当前平台）
COPY --from=base /system/Emby.Server.Implementations.dll /system/MediaBrowser.Model.dll /system/Emby.Web.dll ./dllin/
COPY --from=base /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js /system/dashboard-ui/embypremiere/embypremiere.js /system/dashboard-ui/modules/common/usersettings/usersettingsbuilder.js ./jsin/
COPY --from=base /system/dashboard-ui/index.html ./htmlin/
COPY --from=base /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js ./webin/

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

# 归集破解产物到镜像路径结构 /out/（阶段D 一条 COPY 到位）
#   /out/system/Emby.Server.Implementations.dll / MediaBrowser.Model.dll / Emby.Web.dll
#   /out/system/dashboard-ui/modules/emby-apiclient/connectionmanager.js
#   /out/system/dashboard-ui/embypremiere/embypremiere.js
#   /out/system/dashboard-ui/modules/common/usersettings/usersettingsbuilder.js
#   /out/system/dashboard-ui/index.html
RUN mkdir -p /out/system/dashboard-ui/modules/emby-apiclient /out/system/dashboard-ui/embypremiere /out/system/dashboard-ui/modules/common/usersettings && \
    cp ./dllout/Emby.Server.Implementations.dll ./dllout/MediaBrowser.Model.dll ./webout/Emby.Web.dll /out/system/ && \
    cp ./jsout/connectionmanager.js /out/system/dashboard-ui/modules/emby-apiclient/ && \
    cp ./jsout/embypremiere.js /out/system/dashboard-ui/embypremiere/ && \
    cp ./jsout/usersettingsbuilder.js /out/system/dashboard-ui/modules/common/usersettings/ && \
    cp ./htmlout/index.html /out/system/dashboard-ui/

# ---- 阶段D: 最终镜像 = base + 破解 + 增强 + amilys 触发链 ----
FROM base

# ===== 1+2+3) 破解产物（DLL + JS + index.html，已由 patcher 归集到 /out/system/）=====
#    一条 COPY 到位：/out/system/... → /system/...
COPY --from=patcher /out/ /

# ===== 4+5+6) 前端增强 + 触发链（本地 emby/，已按镜像路径结构组织）=====
#    一条 COPY 到位：emby/system/... → /system/...，emby/etc/... → /etc/...
COPY emby/ /

# 可执行位
RUN chmod +x /etc/ext.sh /etc/regoff.sh /etc/services.d/emby-server/run /etc/services.d/emby-server/finish