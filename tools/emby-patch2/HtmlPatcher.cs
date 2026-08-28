using System;
using System.IO;

namespace EmbyPatch2
{
    // ===================================================================
    // HTML patch：复刻 amilys index.html 加载链（适配任意 Emby 版本）
    //
    // amilys 实测 index.html 引用顺序（关键）:
    //   <link href="emby-crx/style.css">          ← emby-crx 美化 CSS
    //   <script src="emby-crx/common-utils.js">
    //   <script src="emby-crx/jquery-3.6.0.min.js">
    //   <script src="emby-crx/md5.min.js">
    //   <script src="emby-crx/config.js">
    //   <script src="emby-crx/main.js">
    //   <script src="apploader.js" defer>
    //   <script data-main="ext" src="require.js">  ← require.js 加载 ext.js
    //
    // 注意: embyLaunchPotplayer.js 不在 index.html 直接引用！
    //       它由 ext.js 的 extmod（ext.sh 启动时注入）作为 AMD 模块动态加载。
    //       这样模块在播放页就绪后加载，外部播放器按钮才插到播放按钮之后。
    //       直接 <script> 引用会在播放按钮渲染前执行 → 按钮位置跑到上面。
    //
    // 幂等：已含 emby-crx 或 data-main="ext" 则跳过。
    // 用法: EmbyPatch2 html <输入> <输出>
    // ===================================================================
    internal static class HtmlPatcher
    {
        // emby-crx 静态引用块（放 </head> 前，与 amilys 一致）
        private const string CrxBlock =
            "<link rel=\"stylesheet\" id=\"theme-css\" href=\"emby-crx/style.css\" type=\"text/css\" media=\"all\" />\n" +
            "<script src=\"emby-crx/common-utils.js\"></script>\n" +
            "<script src=\"emby-crx/jquery-3.6.0.min.js\"></script>\n" +
            "<script src=\"emby-crx/md5.min.js\"></script>\n" +
            "<script src=\"emby-crx/config.js\"></script>\n" +
            "<script src=\"emby-crx/main.js\"></script>\n";

        // require.js 加载 ext.js（放 </head> 前，与 amilys 一致）
        private const string RequireBlock =
            "<script data-main=\"ext\" src=\"require.js\"></script>\n";

        private const string MarkerCrx = "emby-crx/style.css";
        private const string MarkerReq = "data-main=\"ext\"";

        public static int Patch(string input, string output)
        {
            var s = File.ReadAllText(input);

            // 幂等：两个标记都在就跳过
            if (s.Contains(MarkerCrx) && s.Contains(MarkerReq))
            {
                Console.WriteLine("  [HTML] 已包含 emby-crx + require.js(ext) 引用，跳过（幂等）");
                File.WriteAllText(output, s);
                return 0;
            }

            var idx = s.IndexOf("</head>", StringComparison.OrdinalIgnoreCase);
            if (idx < 0)
            {
                Console.WriteLine("  [HTML] !! 未找到 </head> 锚点，保持原文件");
                File.Copy(input, output, true);
                return 0;
            }

            var block = "";
            if (!s.Contains(MarkerCrx)) block += CrxBlock;
            if (!s.Contains(MarkerReq)) block += RequireBlock;

            s = s.Insert(idx, block);
            Console.WriteLine($"  [HTML] 已注入 emby-crx 引用 + require.js(ext) ({s.Length} chars)");
            File.WriteAllText(output, s);
            return 0;
        }
    }
}