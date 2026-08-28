#!/usr/bin/env python3
"""git 提交+推送：归类整理后的项目（触发 GitHub Actions 编译）"""
import os, subprocess

REPO = "/www/project/emby_patch"

def run(cmd, timeout=180):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    return r.stdout.strip() or r.stderr.strip()

def main():
    os.chdir(REPO)
    print("=== 1) git status（确认待提交）===")
    print(run("git status --short | head -25"))
    print("\n=== 2) 确认 .gitignore（patcher-bin 应跟踪、archive 应忽略）===")
    print("  patcher-bin 被忽略？", run("git check-ignore patcher-bin/EmbyPatch2.dll 2>&1 || echo '否(将上传)'"))
    print("  archive 被忽略？", run("git check-ignore archive/ 2>&1 || echo '否'"))
    print("\n=== 3) git add -A ===")
    print(run("git add -A"))
    print("\n=== 4) 待提交文件数 ===")
    print(run("git diff --cached --name-only | wc -l"))
    print("\n=== 5) commit ===")
    print(run('git commit -m "reorganize: 归类工具(tools/)+清理临时文件+patcher-bin上传+workflow同步" 2>&1 | tail -4'))
    print("\n=== 6) push（触发 GitHub Actions）===")
    print(run("git push -u origin main 2>&1 | tail -6"))

if __name__ == "__main__":
    main()