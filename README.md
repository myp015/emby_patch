# emby_patch — Emby 增强镜像（复刻 amilys 方案 + 前端增强三件套直嵌）

> 项目性质：技术研究与项目管理用。基于官方 `emby/embyserver` 镜像构建，集成前端增强功能。

## 目标
官方 `emby/embyserver` 镜像 → 构建期自动 patch → 前端增强三件套直接嵌入 index.html → multi-arch → 推送私有库 `kulai.ainas.cc` / `docker.ainas.cc:5200`。

## 前端增强（直接嵌入 index.html，apploader.js 之后）
| 文件 | 作用 | 加载方式 |
|---|---|---|
| `embyHappy.js` | 破解注册信息注入（localStorage） | index.html 直接 `<script>` |
| `embyLaunchPotplayer.js` | 外部播放器 | index.html 直接 `<script>` |
| `swiper_v2/home-swiper.js` | 首页海报轮播 | index.html 直接 `<script>` |

> 已删除：emby-crx 全家桶 / ext.sh / ext.js / require.js / danmaku.min.js / extmod 机制。
> 三者均依赖 Emby 全局 require/apploader 环境 → 统一插在 apploader.js 之后。

## 镜像内前端加载链
```
index.html（HtmlPatcher v5 构建期从 base 提取 + 动态注入，任意版本适配）:
  <body>: apploader.js（Emby 主应用）
          embyHappy.js          ← 直接 <script> 引用
          embyLaunchPotplayer.js ← 直接 <script> 引用（自执行，开箱即用）
          swiper_v2/home-swiper.js ← 直接 <script> 引用（IIFE 自执行）
```

## 启动触发链（复刻 amilys，容器每次启动）
```
/init → s6 → /etc/services.d/emby-server/run:
  1. mkdir -p /config/config          ← 修复：空 /config 卷首次启动目录不存在
  2. /etc/regoff.sh                   ← 写 mb.lic + hosts + 注册配置
  3. 启动 EmbyServer（处理 PUID/PGID/UMASK/dri）
```

## 目录结构
```
emby/                        # ★ 资源根（web + files + config 的统一拷贝，构建用此目录）
  system/dashboard-ui/       # 前端增强（构建期覆盖 base 对应文件）
    embyHappy.js             # 破解注册注入
    embyLaunchPotplayer.js   # 外部播放器（老板指定源，内置图标，无 CDN 依赖）
    swiper_v2/home-swiper.js # 首页海报轮播
  etc/                       # 触发链（regoff.sh / services.d）
tools/
  emby-patch2/               # EmbyPatch2 源码（Mono.Cecil）
    Program.cs               # 入口（DLL/JS/HTML/webdll 四种模式）
    JsPatcher.cs             # JS 字符串替换（connectionmanager/embypremiere/usersettingsbuilder）
    HtmlPatcher.cs           # HTML 注入（前端增强三件套，apploader 后，清洗重注入，幂等）
    WebDllPatcher.cs         # 嵌入破解版 connectionmanager.js 到 Emby.Web.dll
patcher-bin/                 # EmbyPatch2 本地预编译产物（构建期 COPY，避免 buildx 卡死）
Dockerfile                   # 多阶段：base → patcher(COPY patcher-bin, patch) → final
build.sh                     # 一键构建（本地 arm64 验证；--push 上传 multi-arch）
```

## EmbyPatch2 工具（patcher-bin）
支持 4 种模式，**语义匹配**（非字节偏移，跨 4.9.x 有适应性，换版本后需验证 patch 点命中）：
```
EmbyPatch2 <输入DLL> <输出DLL> [伪服务器URL]   # DLL IL patch（URL + set_registered + IsMBSupporter）
EmbyPatch2 js <输入JS> <输出JS>                # JS 字符串替换（connectionmanager/embypremiere/usersettingsbuilder）
EmbyPatch2 html <输入index> <输出index>        # index.html 注入前端增强三件套（apploader 后）
EmbyPatch2 webdll <Web.dll> <破解cm.js> <输出> # 嵌入破解 connectionmanager.js 到 Emby.Web.dll
```
- 源码改动后重新发布：`export PATH=$PATH:/root/.dotnet && dotnet publish tools/emby-patch2 -c Release -o patcher-bin`
- 无 patch 点返回 0 保持原文件（幂等，不中断构建）

## 构建 / 推送
```bash
./build.sh                       # 本地 arm64 验证（不上传）
./build.sh --push                # amd64 + arm64 multi-arch 上传 latest + 版本号
EMBY_VERSION=4.9.5.0 ./build.sh --push  # 指定官方基础版本
REGISTRY=docker.ainas.cc:5200 ./build.sh --push  # 指定私有库
```
依赖：docker buildx、`patcher-bin/`（已发布）、`emby/` 资源目录。

## GitHub Actions 工作流（仅手动触发）
- `build-emby-swiper_v2.yml`：构建前端增强三件套镜像（无 SKIN 参数，Dockerfile 固定逻辑）
- 流程：checkout → .NET8 → `dotnet publish tools/emby-patch2 -o patcher-bin` → buildx → login 私有库（secrets）→ `buildx --platform linux/amd64,linux/arm64 --push`
- 输入：`emby_version`（默认 latest 自动探测）、`registry`（kulai.ainas.cc 默认 / docker.ainas.cc:5200）
- Secrets：`REGISTRY_USERNAME` / `REGISTRY_PASSWORD`

## Patch 内容详解（DLL + JS）

> 以下内容来自 `tools/emby-patch2/` 源码，基于官方源文件语义匹配。研究记录用。

### DLL IL patch（`Program.cs`，Mono.Cecil 实现）
```
① Emby.Server.Implementations.dll — 验证 URL 替换（<UpdateRegistrationStatus>d__26::MoveNext）
   匹配: Ldstr 且含 "mb3admin.com" + "registration/validate" → 替换为伪服务器 URL
② Emby.Server.Implementations.dll — set_registered 强制 true
   匹配: ldc.i4.0 后紧跟 callvirt set_registered → ldc.i4.1
③ MediaBrowser.Model.dll — IsMBSupporter 恒 true
   匹配: get_IsMBSupporter 方法体 → ldc.i4.1; ret
```
> 语义匹配（方法名 + IL 模式），非字节偏移 → 跨 4.9.x 有适应性。无 patch 点返回 0 保持原文件。

### JS 字符串替换（`JsPatcher.cs`，按文件名自动识别）
```
① connectionmanager.js: validateDevice URL→/?、缓存365、伪造200、lastValidDate→Date.now()
② embypremiere.js: getStatus→/、伪造 Lifetime JSON
③ usersettingsbuilder.js: drawerStyle/settingsDrawerStyle 默认值 docked→closed（侧边栏默认关闭）
```

### HTML 注入（`HtmlPatcher.cs`，index.html 动态生成）
```
1) 清洗：移除旧注入（emby-crx 皮肤 / home-swiper / embyHappy / embyLaunchPotplayer / require.js data-main=ext）
2) 重注入：apploader.js 完整标签后 → embyHappy + embyLaunchPotplayer + swiper_v2/home-swiper
   （找不到 apploader 则兜底 </body> 前；幂等，重复执行不重复注入）
```

### Web.dll 嵌入（`WebDllPatcher.cs`）
```
把破解版 connectionmanager.js 替换嵌入到 Emby.Web.dll 的
嵌入资源 Emby.Web.dashboard_ui.modules.emby_apiclient.connectionmanager.js
```

## 与 amilys 一致性
- 前端资源：与 amilys 提取版一致（除 embyLaunchPotplayer 为老板指定新版源）
- 有意差异：
  1. embyLaunchPotplayer.js：老板指定新版源（内置图标）
  2. 前端增强三件套直接嵌入 index.html（不再走 ext.sh / require.js / extmod）
  3. run 脚本加 `mkdir -p /config/config`（修复空卷首次启动 cp 失败）
  4. regoff.sh 无条件写 mb.lic（修复目录已存在时跳过）
  5. usersettingsbuilder.js：侧边栏默认关闭（源码级）
  6. 移除官方 s6-overlay 原生 emby-server 服务（修复 4.10 无限重启）
