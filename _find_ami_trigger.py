#!/usr/bin/env python3
"""精确定位 amilys 容器里谁执行 /config/config/ext.sh（或等价扩展脚本机制）
方法：全盘 grep 二进制+文本，找 ext.sh / config/config / extmod 的执行引用"""
import os, subprocess, shutil, re

AMI = "/www/project/emby_patch/_dbg_amilys2"

def run(cmd, timeout=600):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout.strip(), r.stderr.strip()

def main():
    shutil.rmtree(AMI, ignore_errors=True)
    os.makedirs(AMI, exist_ok=True)
    run("docker pull amilys/embyserver:latest >/dev/null 2>&1")
    cid = run("docker create amilys/embyserver:latest")[1]
    # 提取整个容器关键启动区域
    for p in ["/init", "/etc", "/package", "/root", "/usr", "/opt", "/sbin", "/bin", "/config"]:
        name = p.strip("/").replace("/", "_")
        run(f"docker cp {cid}:{p} {AMI}/fs_{name} 2>/dev/null")
    run(f"docker cp {cid}:/system/dashboard-ui/index.html {AMI}/amilys_index.html")
    run(f"docker cp {cid}:/system/dashboard-ui/ext.js {AMI}/amilys_ext.js")
    run(f"docker cp {cid}:/system/dashboard-ui/require.js {AMI}/amilys_require.js")
    run(f"docker cp {cid}:/system/dashboard-ui/emby-crx/main.js {AMI}/amilys_crx_main.js")
    run(f"docker rm -f {cid}")

    print("=== 1) 全盘搜索 ext.sh 引用（任何文件含字符串 'ext.sh'）===")
    r = run(f"grep -rla 'ext\\.sh' {AMI} 2>/dev/null | head -20")
    hits = [x for x in r[1].splitlines() if x.strip()]
    print("  命中:", hits or "(无)")
    for f in hits[:10]:
        try:
            content = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        for line in content.splitlines():
            if "ext.sh" in line:
                print(f"    {f}: {line.strip()[:150]}")

    print("\n=== 2) 全盘搜索 '/config/config' 或 'extmod' 或 'sed -i' 引用 ===")
    r = run(f"grep -rla 'config/config\\|extmod\\|sed -i' {AMI} 2>/dev/null | head -20")
    hits = [x for x in r[1].splitlines() if x.strip()]
    print("  命中:", hits or "(无)")
    for f in hits[:10]:
        try:
            content = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        for line in content.splitlines():
            if "config/config" in line or "extmod" in line or "sed -i" in line:
                print(f"    {f}: {line.strip()[:150]}")

    print("\n=== 3) /init 完整内容（启动链）===")
    try:
        init = open(f"{AMI}/fs_init", encoding="utf-8", errors="ignore").read()
        print(init[:3000])
    except Exception as e:
        print("  init 提取失败:", e)

    print("\n=== 4) s6-overlay 服务树（含 user bundle 完整）===")
    r = run(f"find {AMI}/fs_etc -maxdepth 5 2>/dev/null | head -80")
    print(r[1] or "(无)")

    print("\n=== 5) /etc/cont-init.d 或 services.d 是否有扩展钩子 ===")
    r = run(f"find {AMI}/fs_etc -name 'cont-init*' -o -name '*.up' -o -name 'run' -o -name 'exec' 2>/dev/null | head -30")
    print(r[1] or "(无)")

    print("\n=== 6) amilys index.html 完整 script 顺序（body 部分）===")
    s = open(f"{AMI}/amilys_index.html", encoding="utf-8", errors="ignore").read()
    scripts = re.findall(r'<script[^>]*src="([^"]*)"[^>]*>', s)
    print("  script 顺序:")
    for i, sc in enumerate(scripts):
        print(f"    [{i}] {sc}")
    print("\n  </body> 前 800 字符:")
    body_end = s.lower().rfind("</body>")
    print("  " + s[max(0, body_end-800):body_end])

if __name__ == "__main__":
    main()