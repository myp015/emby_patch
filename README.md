# emby_patch — Emby 破解增强（复刻 amilys 方案 + emby-crx + 外部播放器）

## 目标
官方 `emby/embyserver` 镜像 → 构建期自动 patch（DLL+JS+HTML）→ 集成 **amilys 版 emby-crx** + **embyLaunchPotplayer（外部播放器）** → multi-arch → 推送私有库 `kulai.ainas.cc/emby/embyserver`。

## 破解点（与 amilys 破解 md5/IL 双重验证一致，全部基于官方源文件）
| 文件 | 改动 |
|---|---|
| Emby.Server.Implementations.dll | 验证URL→伪服务器(emby.ssr0.cn:433) + set_registered 强制 true |
| MediaBrowser.Model.dll | get_IsMBSupporter 恒 true |
| Emby.Web.dll | 无逻辑改动（幂等保留） |
| connectionmanager.js | validateDevice URL→本地 /?, 缓存365, 伪造成功 |
| embypremiere.js | getStatus→本地 /, 伪造 Lifetime 响应 |

## 前端加载链（复刻 amilys，含 ext.sh 扩展机制）
```
index.html（HtmlPatcher 构建期注入，任意版本适配）:
  → emby-crx/style.css + common-utils/jquery/md5/config/main.js（静态）
  → <script data-main="ext" src="require.js">（动态入口）
require.js → ext.js:
  const extmod=["embyLaunchPotplayer","ede.user","actorPlus"]  ← ext.sh 启动时 sed 注入
  require(['embyHappy']) + require(extmod, ...)
→ 异步加载模块（页面渲染后执行）
  → embyLaunchPotplayer.js → 外部播放器按钮插入播放按钮之后（✅ 位置正确）
  → ede.user.js（弹幕）/ actorPlus.js（隐藏未知演员）
```

## 扩展机制（任务1：amilys 模式 ext.sh）
`config/config/ext.sh` → 容器每次启动运行 → `sed -i "/extmod/s/\[.*\]/$extmod/g" /system/dashboard-ui/ext.js`
- extmod 数组控制加载哪些扩展模块（embyLaunchPotplayer / ede.user / actorPlus）
- MediaId 控制 emby-crx 美化范围（可选）
- 用户可改此文件后重启容器生效

## embyLaunchPotplayer（任务2：指定源）
- 来源：http://47.103.159.168:8008/urlbash/embyscript/embyLaunchPotplayer.sh（老板指定）
- 存放：web/embyLaunchPotplayer.js（require.js 模块）+ files/embyLaunchPotplayer.js（归档）
- 注入位置（任务3 修复）：**不 head 直接引用**（会跑到播放按钮上面），
  由 require.js 经 ext.js/ext.sh 异步加载 → 播放页就绪后插入播放按钮之后

## 目录结构
```
patch2/            # EmbyPatch2 源码（Mono.Cecil）：DLL IL + JS + HTML 三种 patch 模式
  Program.cs       # DLL 语义 patch（URL + set_registered）
  JsPatcher.cs     # JS 字符串替换（connectionmanager/embypremiere）
  HtmlPatcher.cs   # HTML 注入（emby-crx 静态引用 + data-main="ext" require.js，幂等、版本无关）
Dockerfile         # 多阶段：base → patcher(patch DLL/JS/HTML) → final(COPY 模块/ext.sh)
build.sh           # 一键构建（本地 arm64 验证；--push 上传 multi-arch）
web/
  emby-crx/        # amilys 版前端增强（style.css + 5 js，从容器提取）
  ext.js           # require 入口（extmod 由 ext.sh 注入）
  require.js       # 加载器
  embyLaunchPotplayer.js  # 外部播放器（老板指定源，异步加载）
  ede.user.js      # 弹幕
  actorPlus.js     # 隐藏未知演员
  embyHappy.js     # 附加增强
config/config/ext.sh  # 启动扩展脚本（amilys 模式）
.github/workflows/build.yml  # GitHub Actions：publish → buildx multi-arch → push 私有库
```

## GitHub Actions 工作流
- 触发：push main / 手动
- 流程：checkout → .NET8 → `dotnet publish patch2` → buildx → login 私有库（secrets）→ `buildx --platform linux/amd64,linux/arm64 --push`
- Secrets：`REGISTRY_USERNAME` / `REGISTRY_PASSWORD`（kulai.ainas.cc）