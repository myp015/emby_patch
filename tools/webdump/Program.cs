using System;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

namespace WebDump
{
    // ===================================================================
    // 列出 Emby.Web.dll 的嵌入资源（EmbeddedResource 在 Module.Resources 层）
    // 用法: WebDump <dll路径> [输出文件]
    // ===================================================================
    internal static class Program
    {
        static int Main(string[] args)
        {
            if (args.Length < 1)
            {
                Console.WriteLine("用法: WebDump <dll> [输出文件]");
                return 1;
            }
            var sw = args.Length > 1 ? new StreamWriter(args[1]) : null;
            Action<string> log = s => { Console.WriteLine(s); sw?.WriteLine(s); };

            var resolver = new DefaultAssemblyResolver();
            resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(args[0])));
            var rp = new ReaderParameters { AssemblyResolver = resolver };
            using var asm = AssemblyDefinition.ReadAssembly(args[0], rp);

            log($"程序集: {asm.Name.Name} v{asm.Name.Version}");
            log($"模块: {asm.MainModule.Name}");
            log($"嵌入资源总数: {asm.MainModule.Resources.Count}");
            log("\n=== 嵌入资源清单 ===");
            foreach (var res in asm.MainModule.Resources)
            {
                if (res is EmbeddedResource er)
                    log($"  [embedded] {er.Name} ({er.GetResourceData().Length}B)");
                else
                    log($"  [{res.GetType().Name}] {res.Name}");
            }
            sw?.Flush(); sw?.Dispose();
            return 0;
        }
    }
}