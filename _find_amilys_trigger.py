#!/usr/bin/env python3
"""深挖 amilys 的 ext.sh 启动触发机制（s6-overlay / init / package 全链）"""
import os, subprocess, shutil, re

AMI = "/www/project/emby_patch/_amilys_trigger"
def run(cmd, timeout=300):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout.strip(), r.stderr.strip()

def main():
    shutil.rmtree(AMI, ignore_errors=True)
    os.makedirs(AMI, exist_ok=True)
    run("docker pull amilys/embyserver:latest >/dev/null 2>&1")
    cid = run("docker create amilys/embyserver:latest")[1]
    # 提取全部启动相关
    for p, name in [("/init","init"), ("/etc/s6-overlay","s6"), ("/package","package"),
                    ("/usr/bin","usrbin"), ("/usr/sbin","usrsbin"), ("/config","config")]:
        run(f"docker cp {cid}:{p} {AMI}/{name} 2>/dev/null")
    run(f"docker rm -f {cid}")

    print("=== 1) s6-overlay 完整树（含所有 bundle/服务）===")
    r = run(f"find {AMI}/s6 -maxdepth 6 2>/dev/null | head -120")
    print(r[1] or "(无)")

    print("\n=== 2) 找 user bundle 的 contents.d 内容（服务清单）===")
    for p in ["user","user2","default","s6rc"]:
        r = run(f"ls {AMI}/s6/s6-rc.d/{p}/contents.d/ 2>/dev/null")
        print(f"  [{p}] contents.d:", r[1] or "(空)")

    print("\n=== 3) 找所有 up/run/finish 脚本并 grep ext ===")
    r = run(f"find {AMI}/s6 -name up -o -name run -o -name finish 2>/dev/null | head -40")
    for f in [x for x in r[1].splitlines() if x.strip()]:
        try:
            c = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        if re.search(r"ext|config|sed|dashboard", c, re.I):
            print(f"  ★ {f}")
            print("  " + c[:600])

    print("\n=== 4) /init 全文 ===")
    try:
        print(open(f"{AMI}/init", encoding="utf-8", errors="ignore").read()[:1500])
    except Exception as e:
        print("  err:", e)

    print("\n=== 5) 全盘 grep 'ext.md5' / 'ext.sh' / 'config/config'（精确字符）===")
    r = run(f"grep -rla 'ext\\.sh\\|config/config\\|extmd\\|/config/' {AMI} 2>/dev/null | head -20")
    hits = [x for x in r[1].splitlines() if x.strip()]
    print("  命中:", hits or "(无)")
    for f in hits[:10]:
        try:
            c = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        for line in c.splitlines():
            if re.search(r"ext\.sh|config/config|ext", line, re.I):
                print(f"    {f}: {line.strip()[:150]}")

    print("\n=== 6) 镜像 Dockerfile 线索（package 里的 s6rc 脚本）===")
    r = run(f"find {AMI}/package -maxdepth 4 2>/dev/null | head -40")
    print(r[1] or "(无)")

if __name__ == "__main__":
    main()