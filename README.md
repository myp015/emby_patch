# emby_patch — Emby 4.9 破解增强（复刻 amilys 方案，官方源文件语义 patch）

## 目标
官方 `emby/embyserver` 镜像 → 构建期自动 patch（DLL+JS+HTML）→ 集成 **amilys 版 emby-crx** 前端增强 → multi-arch → 推送私有库 `kulai.ainas.cc/emby/embyserver`。

## 破解点（与 amilys 破解 md5/IL 双重验证一致，全部基于官方源文件）
| 文件 | 改动 |
|---|---|
| Emby.Server.Implementations.dll | 验证URL→伪服务器(emby.ssr0.cn:433) + set_registered 强制 true |
| MediaBrowser.Model.dll | get_IsMBSupporter 恒 true |
| Emby.Web.dll | 无逻辑改动（幂等保留） |
| connectionmanager.js | validateDevice URL→本地 /?, 缓存365, 伪造成功 |
| embypremiere.js | getStatus→本地 /, 伪造 Lifetime 响应 |
| index.html | 构建期从 base 提取，动态插入 emby-crx + potplayer 引用（**适配任意版本，不 COPY 固定文件**） |

## amilys 版 emby-crx（web/emby-crx/）
从 amilys/embyserver 容器内提取（官方 Nolovenodie 版不支持 4.9）：
common-utils.js / config.js / jquery-3.6.0.min.js / main.js / md5.min.js / style.css
增强 JS（files/）：embyLaunchPotplayer.js / embyHappy.js / ede.user.js / danmaku.min.js

## 工具结构
```
patch2/          # EmbyPatch2 源码（Mono.Cecil）：DLL IL patch + JS patch + HTML patch(新增)
  Program.cs     # DLL 语义 patch（URL + set_registered）
  JsPatcher.cs   # JS 字符串替换（connectionmanager/embypremiere）
  HtmlPatcher.cs # HTML 动态插入（任意 index.html 版本适配，幂等）
Dockerfile       # 多阶段：base → patcher(patch DLL/JS/HTML) → final
.github/workflows/build.yml  # GitHub Actions：dotnet publish → buildx multi-arch → push 私有库
web/emby-crx/    # amilys 版前端增强资源
files/           # 增强 JS（potplayer/happy/ede/danmaku）
```

## GitHub Actions 工作流（.github/workflows/build.yml）
- 触发：push main / 手动
- 流程：checkout → setup .NET 8 → `dotnet publish patch2` → setup buildx → login 私有库（secrets）→ `buildx build --platform linux/amd64,linux/arm64 --push`
- 需要仓库 Secrets：`REGISTRY_USERNAME`、`REGISTRY_PASSWORD`（kulai.ainas.cc）

## 本地验证（已通过）
- EmbyPatch2 编译 OK；DLL patch 后 PluginSecurityManager IL 与 amilys 破解 0 差异
- JS patch 后 md5 与 amilys 破解完全一致
- HTML patch：任意 index.html 插入引用 + 幂等（已验证）
- 伪服务器 https://emby.ssr0.cn:433/validate 可达（HTTP 200）
