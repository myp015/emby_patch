# syntax=docker/dockerfile:1
# ============================================================
# Emby 官方镜像 + 自动破解/增强（复刻 amilys 方案 + emby-crx 移植）
#
# 关键设计：
#   - 基础: 官方 emby/embyserver:latest（multi-arch，取 amd64+arm64）
#   - 破解: 构建期对 base 的 DLL/JS 做语义 patch（与 amilys 破解一致）
#   - Emby.Web.dll: 按 amilys 方法，把破解版 connectionmanager.js 嵌入其嵌入资源
#     （官方嵌入 40817B=未破解，amilys 嵌入 40766B=破解；我们用 40723B 破解版嵌入）
#   - index.html: 不 COPY 固定文件（不同版本结构不同），构建期从 base 提取
#     后用 HTML 模式动态插入 emby-crx + require.js/ext 入口（幂等、版本无关）
#   - emby-crx: 前端增强/美化资源（从 amilys/Nolovenodie emby-crx 移植）
#   - ext.sh:/config/config/ext.sh 启动时 sed 注入 extmod 到 ext.js（amilys 模式）
#   - 不再在构建期 dotnet publish（buildx 无 NuGet 缓存会卡死），
#     直接 COPY 本机预编译的 patcher-bin 产物
#
# 用法:
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     -t kulai.ainas.cc/emby/embyserver:latest --push .
# ============================================================

# ---- 阶段A: 官方 base（multi-arch，buildx 按平台取）----
FROM emby/embyserver:latest AS base

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
COPY --from=base /system/dashboard-ui/index.html ./htmlin/
COPY --from=base /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js ./webin/

# DLL IL patch（Emby.Server.Implementations + MediaBrowser.Model；Web 幂等保留）
RUN dotnet patcher/EmbyPatch2.dll ./dllin/Emby.Server.Implementations.dll ./dllout/Emby.Server.Implementations.dll && \
    dotnet patcher/EmbyPatch2.dll ./dllin/MediaBrowser.Model.dll ./dllout/MediaBrowser.Model.dll && \
    dotnet patcher/EmbyPatch2.dll ./dllin/Emby.Web.dll ./dllout/Emby.Web.dll
# JS patch（connectionmanager + embypremiere）
RUN dotnet patcher/EmbyPatch2.dll js ./jsin/connectionmanager.js ./jsout/connectionmanager.js && \
    dotnet patcher/EmbyPatch2.dll js ./jsin/embypremiere.js ./jsout/embypremiere.js
# HTML patch（index.html 动态插入 emby-crx + require.js/ext 引入口，任意版本适配）
RUN dotnet patcher/EmbyPatch2.dll html ./htmlin/index.html ./htmlout/index.html
# Web.dll 嵌入破解 connectionmanager.js（复刻 amilys：官方40817→破解版，嵌入改URL）
RUN dotnet patcher/EmbyPatch2.dll js ./webin/connectionmanager.js ./webout/connectionmanager.js && \
    dotnet patcher/EmbyPatch2.dll webdll ./dllin/Emby.Web.dll ./webout/connectionmanager.js ./webout/Emby.Web.dll

# ---- 阶段D: 最终镜像 = base + 破解 + 增强 ----
FROM base

# 破解 DLL（本架构 base 生成，版本天然匹配）+ Web.dll（已嵌入破解 connectionmanager）
COPY --from=patcher /work/dllout/Emby.Server.Implementations.dll /system/Emby.Server.Implementations.dll
COPY --from=patcher /work/dllout/MediaBrowser.Model.dll /system/MediaBrowser.Model.dll
COPY --from=patcher /work/webout/Emby.Web.dll /system/Emby.Web.dll

# 破解 JS（文件系统版）
COPY --from=patcher /work/jsout/connectionmanager.js /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js
COPY --from=patcher /work/jsout/embypremiere.js /system/dashboard-ui/embypremiere/embypremiere.js

# 动态 patch 后的 index.html（含 emby-crx + require.js/ext 引用）
COPY --from=patcher /work/htmlout/index.html /system/dashboard-ui/index.html

# emby-crx 前端增强资源（amilys 容器内提取版，适配 4.9）
COPY web/emby-crx/ /system/dashboard-ui/emby-crx/

# require.js 加载链（复刻 amilys）：ext.js 入口 + require.js 加载器
COPY web/ext.js /system/dashboard-ui/ext.js
COPY web/require.js /system/dashboard-ui/require.js

# 扩展模块（require.js 动态加载，ext.sh 配置 extmod）：
#   embyLaunchPotplayer.js（外部播放器，老板指定源，异步加载→播放按钮之后）
#   embyHappy.js / ede.user.js（弹幕）/ actorPlus.js
COPY files/embyLaunchPotplayer.js /system/dashboard-ui/embyLaunchPotplayer.js
COPY files/embyHappy.js /system/dashboard-ui/embyHappy.js
COPY files/ede.user.js /system/dashboard-ui/ede.user.js
COPY files/actorPlus.js /system/dashboard-ui/actorPlus.js
COPY files/danmaku.min.js /system/dashboard-ui/danmaku.min.js

# ext.sh（/config/config/ext.sh，容器启动时运行，sed 注入 extmod 到 ext.js）
COPY config/config/ext.sh /config/config/ext.sh