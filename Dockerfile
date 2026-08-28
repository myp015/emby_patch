# syntax=docker/dockerfile:1
# ============================================================
# Emby 官方镜像 + 自动破解/增强（复刻 amilys 方案 + emby-crx 移植）
# 
# 关键设计：
#   - 基础: 官方 emby/embyserver:latest（multi-arch，取 amd64+arm64）
#   - 破解: 构建期对 base 的 DLL/JS 做语义 patch（与 amilys 破解一致）
#   - index.html: 不 COPY 固定文件（不同版本结构不同），构建期从 base 提取
#     后用 HTML 模式动态插入 emby-crx + potplayer 引用（幂等、版本无关）
#   - emby-crx: 前端增强/美化资源（从 amilys/Nolovenodie emby-crx 移植）
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
RUN mkdir -p ./dllin ./dllout ./jsin ./jsout ./htmlin ./htmlout

# 提取 base 的原始文件（按当前平台）
COPY --from=base /system/Emby.Server.Implementations.dll ./dllin/
COPY --from=base /system/MediaBrowser.Model.dll ./dllin/
COPY --from=base /system/Emby.Web.dll ./dllin/
COPY --from=base /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js ./jsin/
COPY --from=base /system/dashboard-ui/embypremiere/embypremiere.js ./jsin/
COPY --from=base /system/dashboard-ui/index.html ./htmlin/

# DLL IL patch（Emby.Server.Implementations + MediaBrowser.Model；Web 幂等保留）
RUN dotnet patcher/EmbyPatch2.dll ./dllin/Emby.Server.Implementations.dll ./dllout/Emby.Server.Implementations.dll && \
    dotnet patcher/EmbyPatch2.dll ./dllin/MediaBrowser.Model.dll ./dllout/MediaBrowser.Model.dll && \
    dotnet patcher/EmbyPatch2.dll ./dllin/Emby.Web.dll ./dllout/Emby.Web.dll
# JS patch（connectionmanager + embypremiere）
RUN dotnet patcher/EmbyPatch2.dll js ./jsin/connectionmanager.js ./jsout/connectionmanager.js && \
    dotnet patcher/EmbyPatch2.dll js ./jsin/embypremiere.js ./jsout/embypremiere.js
# HTML patch（index.html 动态插入 emby-crx + potplayer 引用，任意版本适配）
RUN dotnet patcher/EmbyPatch2.dll html ./htmlin/index.html ./htmlout/index.html

# ---- 阶段D: 最终镜像 = base + 破解 + 增强 ----
FROM base

# 破解 DLL（本架构 base 生成，版本天然匹配）
COPY --from=patcher /work/dllout/Emby.Server.Implementations.dll /system/Emby.Server.Implementations.dll
COPY --from=patcher /work/dllout/MediaBrowser.Model.dll /system/MediaBrowser.Model.dll
COPY --from=patcher /work/dllout/Emby.Web.dll /system/Emby.Web.dll

# 破解 JS
COPY --from=patcher /work/jsout/connectionmanager.js /system/dashboard-ui/modules/emby-apiclient/connectionmanager.js
COPY --from=patcher /work/jsout/embypremiere.js /system/dashboard-ui/embypremiere/embypremiere.js

# 动态 patch 后的 index.html（含 emby-crx + potplayer 引用）
COPY --from=patcher /work/htmlout/index.html /system/dashboard-ui/index.html

# emby-crx 前端增强资源（移植自 amilys/Nolovenodie emby-crx）
COPY web/emby-crx/ /system/dashboard-ui/emby-crx/

# 外部播放器增强（embyLaunchPotplayer.js）
COPY files/embyLaunchPotplayer.js /system/dashboard-ui/embyLaunchPotplayer.js
