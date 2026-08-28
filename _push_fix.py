#!/usr/bin/env python3
"""推送修复到 GitHub（触发 Actions 编译 multi-arch 上传私有库）"""
import os, subprocess

REPO = "/www/project/emby_patch"

def run(cmd, timeout=300):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    return r.stdout.strip() or r.stderr.strip()

def main():
    os.chdir(REPO)

    print("=== 1) git status（将提交的文件）===")
    print(run("git status --short 2>&1 | head -30"))

    print("\n=== 2) git add -A ===")
    print(run("git add -A"))

    print("\n=== 3) 待提交文件数 ===")
    print(run("git diff --cached --name-only | wc -l"))

    print("\n=== 4) commit（插件修复：触发链+顺序+extmod默认启用+regoff无条件）===")
    print(run('git commit -m "fix: 插件全部生效 — amilys触发链完整复刻
- HtmlPatcher v3: require.js 注入 apploader.js 之后(body)，emby-crx→head
- services.d/emby-server/run: 每次启动触发 ext.sh + regoff.sh（+mkdir /config/config）
- ext.sh: extmod 默认启用 [embyLaunchPotplayer,ede.user,actorPlus]
- regoff.sh: 无条件写 mb.lic + hosts 伪 mb3admin" 2>&1 | tail -5'))

    print("\n=== 5) push（触发 GitHub Actions）===")
    print(run("git push -u origin main 2>&1 | tail -8"))

    print("\n=== 6) 最新提交 ===")
    print(run("git log --oneline -5"))

if __name__ == "__main__":
    main()