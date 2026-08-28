#!/usr/bin/env python3
"""深挖 amilys 的 ext.sh 触发机制 + index.html 注入位置（apploader/require 在 head 还是 body）"""
import os, subprocess, shutil, re

AMI = "/www/project/emby_patch/_dbg_amilys"
def run(cmd, timeout=300):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout.strip(), r.stderr.strip()

def main():
    shutil.rmtree(AMI, ignore_errors=True)
    os.makedirs(AMI, exist_ok=True)
    run("docker pull amilys/embyserver:latest >/dev/null 2>&1")
    cid = run("docker create amilys/embyserver:latest")[1]
    run(f"docker cp {cid}:/etc/s6-overlay {AMI}/s6-overlay")
    run(f"docker cp {cid}:/init {AMI}/init")
    run(f"docker cp {cid}:/package {AMI}/package")
    run(f"docker cp {cid}:/config {AMI}/config")
    run(f"docker cp {cid}:/root {AMI}/root")
    run(f"docker cp {cid}:/system/dashboard-ui/index.html {AMI}/amilys_index.html")
    run(f"docker rm -f {cid}")

    print("=== 1) amilys s6-overlay 服务树（找 user bundle 内容）===")
    r = run(f"find {AMI}/s6-overlay -maxdepth 3 2>/dev/null | head -60")
    print(r[1] or "(无)")

    print("\n=== 2) user bundle 服务列表（启动的服务）===")
    for b in ["user", "user2"]:
        r = run(f"ls {AMI}/s6-overlay/s6-rc.d/{b}/contents.d/ 2>/dev/null")
        print(f"  [{b}] contents.d:", r[1] or "(空)")

    print("\n=== 3) 所有服务 up 脚本内容（找 ext.sh / /config 调用）===")
    r = run(f"find {AMI}/s6-overlay -name up -not -path '*/s6-*' 2>/dev/null | head -30")
    for f in (r[1] or "").splitlines():
        try:
            c = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        if "ext" in c.lower() or "config" in c.lower():
            print(f"  ★ {f}")
            print("  " + c[:600])

    print("\n=== 4) 全盘搜 'ext.sh' 引用（任何地方）===")
    r = run(f"grep -rl 'ext\\.sh\\|/config/config\\|extmod' {AMI} 2>/dev/null | head -15")
    print("  命中:", r[1] or "(无)")
    for f in (r[1] or "").splitlines():
        try:
            c = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        for line in c.splitlines():
            if "ext" in line.lower() or "config" in line.lower():
                print(f"    {f}: {line.strip()[:120]}")

    print("\n=== 5) amilys index.html 里 apploader.js / require.js 的位置（head 内还是 body 内）===")
    s = open(f"{AMI}/amilys_index.html", encoding="utf-8", errors="ignore").read()
    head_end = s.lower().find("</head>")
    body_start = s.lower().find("<body")
    for kw in ["apploader.js", "require.js"]:
        pos = s.find(kw)
        if pos < 0:
            print(f"  {kw}: 未找到")
            continue
        in_head = pos < head_end
        print(f"  {kw}: 位置={pos} (head_end={head_end}) → {'在 head 内' if in_head else '在 body 内'}")
    # 打印 head 的最后部分（注入块位置）
    print("\n  amilys index.html </head> 前 800 字符:")
    print("  " + s[max(0, head_end-800):head_end])

    print("\n=== 6) amilys config/config 默认内容 ===")
    r = run(f"ls -la {AMI}/config/config/ 2>/dev/null")
    print(r[1] or "(无)")

if __name__ == "__main__":
    main()