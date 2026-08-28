using System;
using System.IO;
using System.Text.RegularExpressions;

namespace EmbyPatch2
{
    // ===================================================================
    // HTML patch（v3 修复版）：复刻 amilys index.html 加载链，适配任意版本
    //
    // amilys 实测 index.html 顺序（关键，来自 amilys 容器真实 index.html）：
    //   <head> 内:  emby-crx/style.css + emby-crx/common-utils/jquery/md5/config/main.js
    //   <body> 末尾: apploader.js → require.js(data-main="ext")
    //   → 先加载 Emby 主应用(apploader)，再加载扩展入口(require.js→ext.js)
    //   → embyLaunchPotplayer/ede.user/actorPlus 由 ext.js 的 extmod 动态加载（ext.sh 启动注入）
    //
    // v3 修复（解决"插件全部不生效"）:
    //   1. 不再"幂等跳过"——旧镜像 index.html 已被旧版注入成错误顺序
    //      （require.js 在 head、apploader 顺序反了），必须清洗后重注入
    //   2. 清洗：移除已有的 emby-crx 引用块 / require.js 注入块（任意位置）
    //   3. 重注入（与 amilys 一致）：
    //      - emby-crx 引用 → </head> 前
    //      - require.js(data-main="ext") → apploader.js 标签之后（body 内）
    //        若找不到 apploader 则插入到 </body> 之前
    //   4. 幂等保护：清洗后重新注入，即使重复执行也保持正确顺序
    //
    // 用法: EmbyPatch2 html <输入index.html> <输出index.html>
    // ===================================================================
    internal static class HtmlPatcher
    {
        // emby-crx 引用块（与 amilys 一致）
        private const string CrxBlock =
            "<link rel=\"stylesheet\" id=\"theme-css\" href=\"emby-crx/style.css\" type=\"text/css\" media=\"all\" />\n" +
            "<script src=\"emby-crx/common-utils.js\"></script>\n" +
            "<script src=\"emby-crx/jquery-3.6.0.min.js\"></script>\n" +
            "<script src=\"emby-crx/md5.min.js\"></script>\n" +
            "<script src=\"emby-crx/config.js\"></script>\n" +
            "<script src=\"emby-crx/main.js\"></script>\n";

        // require.js 加载 ext.js（apploader.js 之后，body 内）
        private const string RequireBlock =
            "<script data-main=\"ext\" src=\"require.js\"></script>\n";

        public static int Patch(string input, string output)
        {
            var s = File.ReadAllText(input);

            // ========== 1) 清洗旧注入（任意顺序下的旧块都移除）==========
            int removedCrx = 0, removedReq = 0;

            // 移除已存在的 emby-crx 引用行（style.css link + 5 个 script，任意顺序）
            var crxRegex = new Regex(
                "<link[^>]*emby-crx/style\\.css[^>]*>\\s*" +
                "|<script[^>]*src=\"emby-crx/[^\"]*\"[^>]*>\\s*",
                RegexOptions.IgnoreCase | RegexOptions.Singleline);
            var m1 = crxRegex.Matches(s);
            removedCrx = m1.Count;
            s = crxRegex.Replace(s, "");

            // 移除已存在的 require.js data-main=ext 注入行（任意位置）
            var reqRegex = new Regex(
                "<script[^>]*data-main=\"ext\"[^>]*src=\"require\\.js\"[^>]*>\\s*" +
                "|<script[^>]*src=\"require\\.js\"[^>]*data-main=\"ext\"[^>]*>\\s*",
                RegexOptions.IgnoreCase | RegexOptions.Singleline);
            var m2 = reqRegex.Matches(s);
            removedReq = m2.Count;
            s = reqRegex.Replace(s, "");

            // ========== 2) 重新注入（与 amilys 一致）==========

            // 2a. emby-crx → </head> 前
            var hi = s.IndexOf("</head>", StringComparison.OrdinalIgnoreCase);
            if (hi < 0) { Console.WriteLine("  [HTML] !! 未找到 </head>"); return 1; }
            s = s.Insert(hi, CrxBlock);

            // 2b. require.js(data-main=ext) → apploader.js 标签之后（body 内）
            int insertAt = -1;
            var ai = s.IndexOf("apploader.js", StringComparison.OrdinalIgnoreCase);
            if (ai >= 0)
            {
                var gt = s.IndexOf('>', ai);
                if (gt >= 0) insertAt = gt + 1;   // 紧跟 apploader.js 标签结束
            }
            if (insertAt < 0)
            {
                var bi = s.IndexOf("</body>", StringComparison.OrdinalIgnoreCase);
                insertAt = bi >= 0 ? bi : s.Length;   // 兜底 </body> 前
            }
            s = s.Insert(insertAt, RequireBlock);

            File.WriteAllText(output, s);

            // ========== 3) 输出诊断 ==========
            Console.WriteLine($"  [HTML] 清洗: 移除 emby-crx×{removedCrx} + require.js×{removedReq}");
            Console.WriteLine($"  [HTML] 重新注入: emby-crx(</head>前) + require.js(apploader后,pos={insertAt})");
            // 验证最终顺序
            var scripts = Regex.Matches(s, "<script[^>]*src=\"([^\"]*)\"[^>]*>");
            Console.Write("  [HTML] 最终 script 顺序:");
            foreach (System.Text.RegularExpressions.Match m in scripts)
                Console.Write($" {m.Groups[1].Value.Split('/')[^1]}");
            Console.WriteLine();
            return 0;
        }
    }
}