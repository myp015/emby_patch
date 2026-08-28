using System;
using System.IO;
using Mono.Cecil;

namespace EmbyPatch2
{
    // ===================================================================
    // Emby.Web.dll 嵌入资源 patch（复刻 amilys 对 Web.dll 的破解）
    //
    // 依据（WebDump 实测官方 vs amilys 的 Emby.Web.dll 嵌入资源）:
    //   官方 Emby.Web.dll 嵌入 7 个资源，唯一被 amilys 改的是:
    //     Emby.Web.dashboard_ui.modules.emby_apiclient.connectionmanager.js
    //   官方 = 40817B（含 mb3admin URL）
    //   amilys = 40766B（破解：URL→伪服务器 + cacheExpirationDays:365 + 伪造200）
    //
    // 本工具: 用 Mono.Cecil 打开官方 Emby.Web.dll，把这个嵌入资源替换为
    //         传入的破解版 connectionmanager.js（我们 patch 文件系统版的产物），
    //         写回 → Web.dll 内部携带破解 JS。
    //
    // 用法: EmbyPatch2 webdll <输入Emby.Web.dll> <破解connectionmanager.js> <输出dll>
    // ===================================================================
    internal static class WebDllPatcher
    {
        const string TargetResource = "Emby.Web.dashboard_ui.modules.emby_apiclient.connectionmanager.js";

        public static int Patch(string inputDll, string jsPath, string outputDll)
        {
            if (!File.Exists(inputDll)) { Console.WriteLine($"  !! 输入DLL不存在: {inputDll}"); return 1; }
            if (!File.Exists(jsPath)) { Console.WriteLine($"  !! 破解JS不存在: {jsPath}"); return 1; }

            var jsData = File.ReadAllBytes(jsPath);
            Console.WriteLine($"  破解JS: {jsPath} ({jsData.Length}B)");

            var resolver = new DefaultAssemblyResolver();
            resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(inputDll)));
            var rp = new ReaderParameters { AssemblyResolver = resolver };

            using var asm = AssemblyDefinition.ReadAssembly(inputDll, rp);
            var module = asm.MainModule;
            bool replaced = false;

            foreach (var res in module.Resources)
            {
                if (res is EmbeddedResource er && er.Name == TargetResource)
                {
                    var oldLen = er.GetResourceData().Length;
                    Console.WriteLine($"  找到嵌入资源: {er.Name} ({oldLen}B)");
                    module.Resources.Remove(res);
                    module.Resources.Add(new EmbeddedResource(TargetResource,
                        ManifestResourceAttributes.Public, jsData));
                    replaced = true;
                    Console.WriteLine($"  已替换为破解版 ({jsData.Length}B)——与 amilys 嵌入版(40766B)同逻辑");
                    break;
                }
            }

            if (!replaced)
            {
                Console.WriteLine($"  !! 未找到嵌入资源 {TargetResource}（版本不同？保持原样）");
                File.Copy(inputDll, outputDll, true);
                return 2;
            }

            asm.Write(outputDll);
            Console.WriteLine($"  输出: {outputDll}");
            return 0;
        }
    }
}