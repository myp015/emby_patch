#!/usr/bin/env python3
"""确认 amilys 是否通过 s6-overlay/cont-init 触发 ext.sh（对比我们缺失的启动钩子）"""
import os, subprocess, shutil, re

AMI = "/www/project/emby_patch/_dbg_amilys3"

def run(cmd, timeout=600):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout.strip(), r.stderr.strip()

def main():
    shutil.rmtree(AMI, ignore_errors=True)
    os.makedirs(AMI, exist_ok=True)
    run("docker pull amilys/embyserver:latest >/dev/null 2>&1")
    cid = run("docker create amilys/embyserver:latest")[1]
    # 提取 /etc 下所有可能与启动相关的
    run(f"docker cp {cid}:/etc {AMI}/etc")
    run(f"docker cp {cid}:/init {AMI}/init")
    run(f"docker cp {cid}:/package {AMI}/package")
    run(f"docker cp {cid}:/usr {AMI}/usr")
    run(f"docker rm -f {cid}")

    print("=== 1) /etc 下所有 cont-init / services 相关 ===")
    r = run(f"find {AMI}/etc -maxdepth 4 2>/dev/null | grep -iE 'cont-init|services.d|s6-rc|ext' | head -40")
    print(r[1] or "(无)")

    print("\n=== 2) 全盘递归搜 'ext.sh' 或 '/config/config'（含二进制、精确）===")
    r = run(f"grep -rla 'ext\\.sh\\|config/config\\|config/config' {AMI} 2>/dev/null | head -20")
    hits = [x for x in r[1].splitlines() if x.strip()]
    print("  命中文件:", hits or "(无)")
    for f in hits[:10]:
        try:
            c = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        for line in c.splitlines():
            if "ext.sh" in line or "config/config" in line:
                print(f"    {f}: {line.strip()[:120]}")

    print("\n=== 3) s6-overlay 是否有 user bundle 或服务（更深的树）===")
    r = run(f"find {AMI}/etc/s6-overlay -maxdepth 6 2>/dev/null | head -100")
    print(r[1] or "(无)")

    print("\n=== 4) /init 全文（s6 启动链，重点看 stage2/cont-init）===")
    try:
        init = open(f"{AMI}/init", encoding="utf-8", errors="ignore").read()
        print(init[:2000])
    except Exception as e:
        print("  init 读取失败:", e)

    print("\n=== 5) 找 s6 的 user/cont-init.d 类脚本内容（是否含 ext 调用）===")
    r = run(f"find {AMI} -name 'up' -o -name 'run' -o -name 'finish' -o -name '*.sh' 2>/dev/null | head -30")
    for f in [x for x in (r[1] or "").splitlines() if x.strip()][:20]:
        try:
            c = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        if "ext" in c.lower() or "config" in c.lower() or "sed" in c:
            print(f"  ★ {f}")
            print("  " + c[:400])

if __name__ == "__main__":
    main()