using System;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

namespace EmbyDump
{
    // ===================================================================
    // 用 Mono.Cecil dump 指定类的所有方法 IL，用于对比官方 vs amilys 破解
    // 用法: EmbyDump <dll路径> <类型名(可含通配/子串)> [输出文件]
    // 例:   EmbyDump Emby.Server.Implementations.dll PluginSecurityManager out.txt
    // ===================================================================
    internal static class Program
    {
        static int Main(string[] args)
        {
            if (args.Length < 2)
            {
                Console.WriteLine("用法: EmbyDump <dll> <类型名子串> [输出文件]");
                return 1;
            }
            var dll = args[0];
            var typeFilter = args[1];
            var outFile = args.Length > 2 ? args[2] : null;

            var sw = outFile != null ? new StreamWriter(outFile) : null;
            Action<string> log = s => { Console.WriteLine(s); sw?.WriteLine(s); };

            using var asm = AssemblyDefinition.ReadAssembly(dll);
            foreach (var type in asm.MainModule.Types)
            {
                // 递归所有嵌套类型
                DumpType(type, typeFilter, log, 0);
            }
            sw?.Flush(); sw?.Dispose();
            Console.WriteLine($"完成。");
            return 0;
        }

        static void DumpType(TypeDefinition type, string filter, Action<string> log, int depth)
        {
            if (type.FullName.Contains(filter) || type.Name.Contains(filter))
            {
                log($"\n===== TYPE: {type.FullName} =====");
                foreach (var m in type.Methods)
                {
                    DumpMethod(m, log);
                }
            }
            foreach (var nested in type.NestedTypes)
            {
                DumpType(nested, filter, log, depth + 1);
            }
        }

        static void DumpMethod(MethodDefinition m, Action<string> log)
        {
            var sig = m.IsStatic ? "static " : "";
            sig += $"{m.ReturnType.FullName} {m.Name}(";
            sig += string.Join(", ", m.Parameters.Select(p => p.ParameterType.FullName + " " + p.Name));
            sig += ")";
            log($"\n--- METHOD: {sig}");
            if (!m.HasBody)
            {
                log("    (abstract/native, no body)");
                return;
            }
            // 打印最大栈、局部变量
            log($"    MaxStack={m.Body.MaxStackSize}, Locals=[{string.Join(", ", m.Body.Variables.Select(v => v.VariableType.FullName))}]");
            foreach (var inst in m.Body.Instructions)
            {
                var operand = FormatOperand(inst.Operand);
                log($"    {inst.Offset:X4}: {inst.OpCode.Name} {operand}");
            }
        }

        static string FormatOperand(object operand)
        {
            if (operand == null) return "";
            if (operand is Instruction ins) return $"IL_{ins.Offset:X4}";
            if (operand is Instruction[] arr) return string.Join(",", arr.Select(x => $"IL_{x.Offset:X4}"));
            if (operand is VariableDefinition v) return $"V_{v.Index}";
            if (operand is ParameterDefinition p) return $"P_{p.Name}";
            if (operand is FieldReference f) return $"field {f.FullName}";
            if (operand is MethodReference mr) return $"call {mr.FullName}";
            if (operand is TypeReference t) return $"type {t.FullName}";
            if (operand is string s) return $"\"{s}\"";
            return operand.ToString();
        }
    }
}