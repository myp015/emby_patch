# emby_patch — Emby 增强镜像（复刻 amilys 方案 + emby-crx + 外部播放器）

> 项目性质：技术研究与项目管理用。基于官方 `emby/embyserver` 镜像构建，集成前端增强功能。

## 目标
官方 `emby/embyserver` 镜像 → 构建期自动 patch → 集成 **amilys 版 emby-crx** + **embyLaunchPotplayer（外部播放器）** + 弹幕 → multi-arch → 推送私有库 `kulai.ainas.cc/emby/embyserver`。

## 镜像内前端加载链（与 amilys 一致）
```
index.html（HtmlPatcher 构建期从 base 提取 + 动态注入，任意版本适配）:
  <head>: emby-crx/style.css + common-utils/jquery/md5/config/main.js（静态美化）
  <body>: apploader.js（Emby 主应用）
          embyLaunchPotplayer.js  ← 直接 <script> 引用（自执行脚本，开箱即用）
          actorPlus.js            ← 直接 <script> 引用（自执行脚本，开箱即用）
          <script data-main="ext" src="require.js">（动态入口）
require.js → ext.js:
  const extmod=["ede.user"]   ← ext.sh 启动时 sed 注入（仅真 AMD 模块）
  require(['embyHappy']) + require(extmod, ...)
→ 异步加载 ede.user.js（弹幕）
```

### 加载策略（重要）
- **自执行脚本**（无 `define()`，Tampermonkey 风格）：embyLaunchPotplayer / actorPlus / emby-crx
  → **index.html 直接 `<script>` 引用**（不走 require.js，开箱即用）
- **真 AMD 模块**（有 `define()`）：ede.user（弹幕）
  → extmod 由 require.js 加载（ext.sh 注入配置）

> ⚠️ 勿把无 `define()` 的自执行脚本放进 extmod 让 require.js 加载——require.js 加载后不执行，插件会失效。

## 启动触发链（复刻 amilys，容器每次启动）
```
/init → s6 → /etc/services.d/emby-server/run:
  1. mkdir -p /config/config          ← 修复：空 /config 卷首次启动目录不存在
  2. 首次 cp /etc/ext.sh → /config/config/ext.sh（用户可改，重启生效）
  3. /etc/regoff.sh                   ← 写 mb.lic + hosts + 注册配置
  4. /config/config/ext.sh            ← sed 注入 MediaId(emby-crx) + extmod(ext.js)
  5. 启动 EmbyServer（处理 PUID/PGID/UMASK/dri）
```

## 目录结构
```
emby/                        # ★ 资源根（web + files + config 的统一拷贝，构建用此目录）
  web/                       # 前端增强
    emby-crx/                # amilys 版（style.css + common-utils/jquery/md5/config/main.js）
    embyLaunchPotplayer.js   # 外部播放器（老板指定源，内置 72.5KB Base64 图标，无 CDN 依赖）
    ede.user.js              # 弹幕（AMD，extmod 加载）
    actorPlus.js             # 隐藏未知演员（自执行）
    embyHappy.js             # 附加增强
    ext.js / require.js      # 动态加载入口
  files/                     # 扩展模块（Dockerfile COPY 用）
  config/                    # 触发链（ext.sh / regoff.sh / services.d）
web/ files/ config/          # emby/ 的源（备份）
tools/
  emby-patch2/               # EmbyPatch2 源码（Mono.Cecil）
    Program.cs               # DLL 语义 patch（URL + set_registered + IsMBSupporter）
    JsPatcher.cs             # JS 字符串替换（connectionmanager/embypremiere）
    HtmlPatcher.cs           # HTML 注入（emby-crx + 自执行脚本 + require.js，清洗重注入）
    WebDllPatcher.cs         # 嵌入破解版 connectionmanager.js 到 Emby.Web.dll
  emby-dump/                 # IL dump 分析工具
  webdump/                   # Web.dll 嵌入资源查看工具
patcher-bin/                 # EmbyPatch2 本地预编译产物（构建期 COPY，避免 buildx 卡死）
Dockerfile                   # 多阶段：base → patcher(COPY patcher-bin, patch DLL/JS/HTML/webdll) → final
build.sh                     # 一键构建（本地 arm64 验证；--push 上传 multi-arch）
```

## EmbyPatch2 工具（patcher-bin）
支持 4 种模式，**语义匹配**（非字节偏移，跨 4.9.x 有适应性，换版本后需验证 patch 点命中）：
```
EmbyPatch2 <输入DLL> <输出DLL> [伪服务器URL]   # DLL IL patch（URL + set_registered + IsMBSupporter）
EmbyPatch2 js <输入JS> <输出JS>                # JS 字符串替换（connectionmanager/embypremiere）
EmbyPatch2 html <输入index> <输出index>        # index.html 注入（emby-crx + 自执行脚本 + require.js）
EmbyPatch2 webdll <Web.dll> <破解cm.js> <输出> # 嵌入破解 connectionmanager.js 到 Emby.Web.dll
```
- 源码改动后重新发布：`export PATH=$PATH:/root/.dotnet && dotnet publish tools/emby-patch2 -c Release -o patcher-bin`
- 无 patch 点返回 0 保持原文件（幂等，不中断构建）

## 构建 / 推送
```bash
./build.sh           # 本地 arm64 验证（不上传）
./build.sh --push    # amd64 + arm64 multi-arch 上传 kulai.ainas.cc/emby/embyserver:latest
```
依赖：docker buildx、`patcher-bin/`（已发布）、`emby/files/embyLaunchPotplayer.js`。

## GitHub Actions 工作流
- 触发：push main / 手动
- 流程：checkout → .NET8 → `dotnet publish tools/emby-patch2 -o patcher-bin` → buildx → login 私有库（secrets）→ `buildx --platform linux/amd64,linux/arm64 --push`
- Secrets：`REGISTRY_USERNAME` / `REGISTRY_PASSWORD`（kulai.ainas.cc）

## Patch 内容详解（DLL + JS）

> 以下内容来自 `tools/emby-patch2/` 源码，基于官方源文件语义匹配，与 amilys 破解对照验证一致。研究记录用。

### DLL IL patch（`Program.cs`，Mono.Cecil 实现）

**① `Emby.Server.Implementations.dll` — 验证 URL 替换**
```
匹配: OpCode == Ldstr 且字符串含 "mb3admin.com" + "registration/validate"
位置: <UpdateRegistrationStatus>d__26::MoveNext 状态机
替换: → https://emby.ssr0.cn:433/validate（伪服务器）
```

**② `Emby.Server.Implementations.dll` — set_registered 强制 true**
```
匹配: ldc.i4.0 后紧跟 callvirt set_registered（两条指令相邻）
位置: <UpdateRegistrationStatus>d__26::MoveNext
替换: ldc.i4.0 → ldc.i4.1
```

**③ `MediaBrowser.Model.dll` — IsMBSupporter 恒 true**
```
匹配: 方法名 get_IsMBSupporter（有方法体）
官方: ldfld <IsMBSupporter>k__BackingField; ret
替换: 清空方法体 → ldc.i4.1; ret
```

> 匹配原则：**语义匹配**（方法名 + IL 模式），非字节偏移 → 跨 4.9.x 有适应性。
> 无 patch 点返回 0 并保持原文件（幂等，不中断构建）。

### JS 字符串替换（`JsPatcher.cs`，按文件名自动识别）

**① `connectionmanager.js` — validateDevice 本地化 + 伪造成功**
```
1. "https://mb3admin.com/admin/service/registration/validateDevice?"  → "/?"
2. "cacheExpirationDays:response.cacheExpirationDays"  → "cacheExpirationDays:365"
   "cacheExpirationDays:0"                            → "cacheExpirationDays:365"
3. "(response||{}).status"                             → "200"
4. "lastValidDate:-1"                                  → "lastValidDate:Date.now()"
```

**② `embypremiere.js` — getStatus 本地化 + 伪造 Lifetime**
```
1. "https://mb3admin.com/admin/service/registration/getStatus"  → "/"
2. fetch("/",{method:"POST",body:key,...}).then(response=>response.json())
   → 直接返回伪造 JSON:
   {"deviceStatus": "0","planType": "Lifetime","subscriptions": {"home": "opve.cn","key": 433493451}}
```

### HTML 注入（`HtmlPatcher.cs`，index.html 动态生成）
```
1) 清洗：移除旧的 emby-crx 引用 / require.js 注入 / 自执行脚本引用（任意顺序，幂等）
2) 重注入：
   head </head> 前:   emby-crx/style.css + common-utils/jquery/md5/config/main.js
   body apploader后:  embyLaunchPotplayer.js + actorPlus.js + require.js(data-main="ext")
```

### Web.dll 嵌入（`WebDllPatcher.cs`）
```
把破解版 connectionmanager.js（40723B）替换嵌入到 Emby.Web.dll 的
嵌入资源 Emby.Web.dashboard_ui.modules.emby_apiclient.connectionmanager.js
（官方 40817B → 破解版；与 amilys 嵌入逻辑一致）
```

## 与 amilys 一致性
- 触发链 ext.sh：与 amilys **逐字符一致**（extmod 默认 `[]`，用户可改 /config/config/ext.sh 启用）
- 有意差异：
  1. embyLaunchPotplayer.js：老板指定新版源（107KB / 内置图标）vs amilys 旧版 20KB
  2. embyLaunchPotplayer / actorPlus 改由 index.html 直接引用（开箱即用，不依赖 extmod）
  3. run 脚本加 `mkdir -p /config/config`（修复空卷首次启动 cp 失败）
  4. regoff.sh 无条件写 mb.lic（修复目录已存在时跳过）
