using System;
using System.IO;

namespace EmbyPatch2
{
    // ===================================================================
    // HTML patch 模式：适配任意 Emby 版本的 index.html
    //
    // 不同版本 index.html 结构不同（资源引用路径/顺序会变），所以不能 COPY
    // 一个写死的 index.html。本模式在构建期从 base 提取原始 index.html，
    // 然后在 </head> 前动态插入：
    //   - emby-crx 资源引用（style.css / common-utils.js / jquery / md5 / main.js）
    //   - embyLaunchPotplayer.js 引用（外部播放器增强）
    //
    // 幂等：若已包含 emby-crx 或 embyLaunchPotplayer 引用则跳过，重复执行不重复插入。
    // 用法: EmbyPatch2 html <输入index.html> <输出index.html>
    // ===================================================================
    internal static class HtmlPatcher
    {
        // 要插入到 </head> 前的引用块（与 amilys script.sh 的注入一致，另加 potplayer）
        private const string InsertBlock =
            "<link rel=\"stylesheet\" id=\"theme-css\" href=\"emby-crx/style.css\" type=\"text/css\" media=\"all\" />\n" +
            "<script src=\"emby-crx/common-utils.js\"></script>\n" +
            "<script src=\"emby-crx/jquery-3.6.0.min.js\"></script>\n" +
            "<script src=\"emby-crx/md5.min.js\"></script>\n" +
            "<script src=\"emby-crx/main.js\"></script>\n" +
            "<script src=\"embyLaunchPotplayer.js\"></script>\n";

        private const string MarkerCss = "emby-crx/style.css";
        private const string MarkerPot = "embyLaunchPotplayer.js";

        public static int Patch(string input, string output)
        {
            var s = File.ReadAllText(input);

            // 幂等检查：已含任一生意引用则跳过
            if (s.Contains(MarkerCss) || s.Contains("id=\"theme-css\""))
            {
                Console.WriteLine("  [HTML] 已包含 emby-crx 引用，跳过（幂等）");
            }
            else if (s.Contains(MarkerPot))
            {
                Console.WriteLine("  [HTML] 已包含 embyLaunchPotplayer 引用，跳过（幂等）");
            }
            else
            {
                // 在 </head> 前插入（不区分大小写兜底）
                var idx = s.IndexOf("</head>", StringComparison.OrdinalIgnoreCase);
                if (idx < 0)
                {
                    Console.WriteLine("  [HTML] !! 未找到 </head> 锚点，保持原文件");
                    File.Copy(input, output, true);
                    return 0;
                }
                s = s.Insert(idx, InsertBlock);
                Console.WriteLine($"  [HTML] 已在 </head> 前插入 emby-crx + embyLaunchPotplayer 引用 ({s.Length} chars)");
            }

            File.WriteAllText(output, s);
            return 0;
        }
    }
}