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
#      → 执行 ext.sh → sed 注入 MediaId(emby-crx/config.js) + extmod(ext.js)
#      → require.js 启动后按 extmod 动态加载 embyLaunchPotplayer/ede.user/actorPlus
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

# ---- 阶段A: 官方 base（multi-arch，buildx 按平台取）----
FROM emby/embyserver:${EMBY_VERSION} AS base

# ---- 阶段P: 运行 patch 工具（用预编译产物，不重新编译）----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS patcher
WORKDIR /work
COPY patcher-bin/ ./patcher/
RUN mkdir -p ./dllin ./dllout ./jsin ./jsout ./htmlin ./htmlout ./webin ./webout

# 提取 base 的原始文件（按当前平台）
COPY --from=base /system/Emby.Server.Implementations.dll ./dllin/
COPY --from=base /system/MediaBrowser.Model.dll ./dllin/
COPY --from=base /system/Emby.Web.dll ./dllin/
COPY --from=base /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js ./jsin/
COPY --from=base /system/dashboard-ui/embypremiere/embypremiere.js ./jsin/
COPY --from=base /system/dashboard-ui/modules/common/usersettings/usersettingsbuilder.js ./jsin/
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
# HTML patch（index.html 动态注入：emby-crx→head，require.js→apploader 后 body）
RUN dotnet patcher/EmbyPatch2.dll html ./htmlin/index.html ./htmlout/index.html
# Web.dll 嵌入破解 connectionmanager.js（复刻 amilys：官方40817→破解版）
RUN dotnet patcher/EmbyPatch2.dll js ./webin/connectionmanager.js ./webout/connectionmanager.js && \
    dotnet patcher/EmbyPatch2.dll webdll ./dllin/Emby.Web.dll ./webout/connectionmanager.js ./webout/Emby.Web.dll

# ---- 阶段D: 最终镜像 = base + 破解 + 增强 + amilys 触发链 ----
FROM base

# ===== 1) 破解 DLL（本架构 base 生成，版本天然匹配）=====
COPY --from=patcher /work/dllout/Emby.Server.Implementations.dll /system/Emby.Server.Implementations.dll
COPY --from=patcher /work/dllout/MediaBrowser.Model.dll /system/MediaBrowser.Model.dll
COPY --from=patcher /work/webout/Emby.Web.dll /system/Emby.Web.dll

# ===== 2) 破解 JS（文件系统版）=====
COPY --from=patcher /work/jsout/connectionmanager.js /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js
COPY --from=patcher /work/jsout/embypremiere.js /system/dashboard-ui/embypremiere/embypremiere.js
COPY --from=patcher /work/jsout/usersettingsbuilder.js /system/dashboard-ui/modules/common/usersettings/usersettingsbuilder.js

# ===== 3) 动态注入后的 index.html（emby-crx→head / require.js→apploader后）=====
COPY --from=patcher /work/htmlout/index.html /system/dashboard-ui/index.html

# ===== 4) 前端增强资源（amilys 容器内提取版，适配 4.9）=====
COPY emby/web/emby-crx/ /system/dashboard-ui/emby-crx/
COPY emby/web/ext.js /system/dashboard-ui/ext.js
COPY emby/web/require.js /system/dashboard-ui/require.js

# ===== 5) 扩展模块（require.js 动态加载，ext.sh 配置 extmod）=====
COPY emby/files/embyLaunchPotplayer.js /system/dashboard-ui/embyLaunchPotplayer.js
COPY emby/files/embyHappy.js /system/dashboard-ui/embyHappy.js
COPY emby/files/ede.user.js /system/dashboard-ui/ede.user.js
COPY emby/files/actorPlus.js /system/dashboard-ui/actorPlus.js
COPY emby/files/danmaku.min.js /system/dashboard-ui/danmaku.min.js

# ===== 6) amilys 触发链（关键！插件生效的最后一环）=====
# 6a. 默认扩展脚本模板（首次启动拷贝到 /config/config/ext.sh）
COPY emby/config/config/ext.sh /etc/ext.sh
# 6b. 注册关闭脚本（写 mb.lic + hosts 伪 mb3admin + 注册配置）
COPY emby/config/regoff.sh /etc/regoff.sh
# 6c. 覆盖官方 s6 服务：每次启动触发 ext.sh + regoff.sh（复刻 amilys）
COPY emby/config/services.d/emby-server/run /etc/services.d/emby-server/run
COPY emby/config/services.d/emby-server/finish /etc/services.d/emby-server/finish
# 6d. 可执行位
RUN chmod +x /etc/ext.sh /etc/regoff.sh /etc/services.d/emby-server/run /etc/services.d/emby-server/finish