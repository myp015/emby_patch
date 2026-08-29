using System;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

namespace EmbyPatch2
{
    // ===================================================================
    // 语义级 DLL patch：复刻 amilys 破解的 2 个改动，作用于官方 DLL
    //
    // 依据（从官方 vs amilys 同版本 IL dump 对比得到）:
    //   1. UpdateRegistrationStatus 状态机 MoveNext 中:
    //      官方: ldstr "https://mb3admin.com/admin/service/registration/validate"
    //      破解: ldstr "https://emby.ssr0.cn:433/validate"   (URL 替换)
    //   2. 同一 MoveNext 中:
    //      官方: ldc.i4.0 → callvirt set_registered(Boolean)   (校验失败标记未注册)
    //      破解: ldc.i4.1 → callvirt set_registered(Boolean)   (强制标记已注册)
    //
    // 用"语义匹配"定位（不是字节偏移，任何版本布局都能 patch）:
    //   - 找包含 mb3admin 的 ldstr → 替换 URL
    //   - 找 ldc.i4.0 后紧跟 set_registered 调用 → 改为 ldc.i4.1
    //
    // 用法: EmbyPatch2 <输入DLL> <输出DLL> [伪服务器URL]
    // ===================================================================
    internal static class Program
    {
        static int Main(string[] args)
        {
            // JS patch 模式: EmbyPatch2 js <输入JS> <输出JS>
            if (args.Length >= 1 && args[0] == "js")
            {
                if (args.Length != 3)
                {
                    Console.WriteLine("用法: EmbyPatch2 js <输入JS文件> <输出JS文件>");
                    return 1;
                }
                return JsPatcher.Patch(args[1], args[2]);
            }

            // HTML patch 模式: EmbyPatch2 html <输入index.html> <输出index.html> [skin]
            //   skin: crx（默认）| swiper_v2 —— 在 </head> 前注入对应首页美化皮肤
            if (args.Length >= 1 && args[0] == "html")
            {
                if (args.Length < 3)
                {
                    Console.WriteLine("用法: EmbyPatch2 html <输入index.html> <输出index.html> [crx|swiper_v2]");
                    return 1;
                }
                var skin = args.Length > 3 ? args[3] : "crx";
                return HtmlPatcher.Patch(args[1], args[2], skin);
            }

            // Web.dll 嵌入资源 patch 模式: EmbyPatch2 webdll <输入Emby.Web.dll> <破解connectionmanager.js> <输出dll>
            // 复刻 amilys：把破解版 connectionmanager.js 替换进 Emby.Web.dll 嵌入资源（与 amilys 嵌入 40766B 同逻辑）
            if (args.Length >= 1 && args[0] == "webdll")
            {
                if (args.Length != 4)
                {
                    Console.WriteLine("用法: EmbyPatch2 webdll <输入Emby.Web.dll> <破解connectionmanager.js> <输出dll>");
                    return 1;
                }
                return WebDllPatcher.Patch(args[1], args[2], args[3]);
            }

            if (args.Length < 2)
            {
                Console.WriteLine("用法: EmbyPatch2 <输入DLL> <输出DLL> [伪服务器URL]");
                return 1;
            }
            var input = args[0];
            var output = args[1];
            var fakeUrl = args.Length > 2 ? args[2] : "https://emby.ssr0.cn:433/validate";

            var resolver = new DefaultAssemblyResolver();
            var inputDir = Path.GetDirectoryName(Path.GetFullPath(input));
            resolver.AddSearchDirectory(inputDir);
            // ★ 修复: 4.10 场景 Mono.Cecil 写入时需解析依赖程序集（如 MediaBrowser.Model）
            //   加搜 base 的 /system（Emby 主 DLL 目录）和当前目录，避免 AssemblyResolutionException
            resolver.AddSearchDirectory("/system");
            resolver.AddSearchDirectory(Environment.CurrentDirectory);
            var rp = new ReaderParameters { AssemblyResolver = resolver };

            using var asm = AssemblyDefinition.ReadAssembly(input, rp);
            int ldstrPatched = 0, boolPatched = 0;

            foreach (var type in asm.MainModule.Types)
                WalkType(type, ref ldstrPatched, ref boolPatched, fakeUrl);

            Console.WriteLine($"patch 统计: URL替换 {ldstrPatched} 处, set_registered布尔 {boolPatched} 处");
            if (ldstrPatched == 0 && boolPatched == 0)
            {
                // 无 patch 点：保持原文件（Emby.Web.dll 本无破解点，这是预期）
                Console.WriteLine("  (无 patch 点，保持原文件——预期行为)");
                File.Copy(input, output, true);
                return 0;
            }
            asm.Write(output);
            Console.WriteLine($"输出: {output}");
            return 0;
        }

        static void WalkType(TypeDefinition type, ref int lp, ref int bp, string fakeUrl)
        {
            foreach (var m in type.Methods)
                if (m.HasBody) PatchMethod(m, ref lp, ref bp, fakeUrl);
            foreach (var n in type.NestedTypes)
                WalkType(n, ref lp, ref bp, fakeUrl);
        }

        static void PatchMethod(MethodDefinition method, ref int lp, ref int bp, string fakeUrl)
        {
            // --- Patch 3: get_IsMBSupporter 方法体恒 true（复刻 amilys MediaBrowser.Model 破解）---
            // 官方: ldfld <IsMBSupporter>k__BackingField; ret
            // 破解: ldc.i4.1; ret
            if (method.Name == "get_IsMBSupporter" && method.HasBody &&
                method.Body.Instructions.Count > 0)
            {
                Console.WriteLine($"  [SUPP] {method.DeclaringType.Name}::{method.Name} -> 恒 true");
                var il = method.Body.GetILProcessor();
                method.Body.Instructions.Clear();
                il.Append(Instruction.Create(OpCodes.Ldc_I4_1));
                il.Append(Instruction.Create(OpCodes.Ret));
                bp++;
                return;
            }

            var insts = method.Body.Instructions;
            for (int i = 0; i < insts.Count; i++)
            {
                var inst = insts[i];
                // --- Patch 1: 仅替换 registration/validate 的验证 URL（与 amilys 破解一致）---
                // 注意: 不能动 appstore/register 和 packages 等其它 mb3admin URL（amilys 没改它们）
                if (inst.OpCode == OpCodes.Ldstr && inst.Operand is string s &&
                    s.Contains("mb3admin.com") && s.Contains("registration/validate"))
                {
                    Console.WriteLine($"  [URL] {method.DeclaringType.Name}::{method.Name} @ {inst.Offset:X4}: \"{s}\"");
                    inst.Operand = fakeUrl;
                    lp++;
                }
                // --- Patch 2: ldc.i4.0 后紧跟 set_registered → 改 ldc.i4.1 ---
                if (inst.OpCode == OpCodes.Ldc_I4_0 && i + 1 < insts.Count)
                {
                    var next = insts[i + 1];
                    if (next.OpCode == OpCodes.Callvirt && next.Operand is MethodReference mr &&
                        mr.Name == "set_registered")
                    {
                        Console.WriteLine($"  [BOOL] {method.DeclaringType.Name}::{method.Name} @ {inst.Offset:X4}: ldc.i4.0 -> ldc.i4.1");
                        inst.OpCode = OpCodes.Ldc_I4_1;
                        bp++;
                    }
                }
            }
        }
    }
}