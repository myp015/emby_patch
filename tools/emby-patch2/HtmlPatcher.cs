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
    //   → embyLaunchPotplayer 由 index.html 直接引用（ext.sh 不再加载）
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
        // 首页美化皮肤块（根据 skin 参数选择）
        //   crx      : emby-crx 全家桶（style.css + common-utils/jquery/md5/config/main.js）
        //   swiper_v2: 单文件 home-swiper.js（自执行，自带 Swiper CSS，无 jQuery 依赖）
        private const string CrxBlock =
            "<link rel=\"stylesheet\" id=\"theme-css\" href=\"emby-crx/style.css\" type=\"text/css\" media=\"all\" />\n" +
            "<script src=\"emby-crx/common-utils.js\"></script>\n" +
            "<script src=\"emby-crx/jquery-3.6.0.min.js\"></script>\n" +
            "<script src=\"emby-crx/md5.min.js\"></script>\n" +
            "<script src=\"emby-crx/config.js\"></script>\n" +
            "<script src=\"emby-crx/main.js\"></script>\n";
        private const string SwiperBlock =
            "<script src=\"emby-crx/home-swiper.js\"></script>\n";

        private static string SkinBlock(string skin) =>
            skin == "swiper_v2" ? SwiperBlock : CrxBlock;

        // require.js 加载 ext.js（apploader.js 之后，body 内）
        private const string RequireBlock =
            "<script data-main=\"ext\" src=\"require.js\"></script>\n";

        // 自执行脚本（Tampermonkey 风格，无 define()，require.js 加载会失效）：
        //   必须直接 <script src> 引用
        //   embyLaunchPotplayer.js 外部播放器（107KB 老板指定源，监听 viewbeforeshow+DOM）
        private const string DirectScriptsBlock =
            "<script src=\"embyLaunchPotplayer.js\"></script>\n";

        public static int Patch(string input, string output, string skin = "crx")
        {
            var s = File.ReadAllText(input);

            // ========== 1) 清洗旧注入（任意顺序下的旧块都移除）==========
            int removedCrx = 0, removedReq = 0;

            // 移除已存在的皮肤引用（emby-crx 全家桶 + home-swiper.js，任意顺序）
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

            // 移除已存在的 embyLaunchPotplayer.js 直接引用（避免重复注入）
            var directRegex = new Regex(
                "<script[^>]*src=\"embyLaunchPotplayer\\.js\"[^>]*>\\s*",
                RegexOptions.IgnoreCase | RegexOptions.Singleline);
            var mDirect = directRegex.Matches(s);
            s = directRegex.Replace(s, "");

            // ========== 2) 重新注入（与 amilys 一致）==========

            // 2a. 皮肤（emby-crx 或 swiper_v2） → </head> 前
            var hi = s.IndexOf("</head>", StringComparison.OrdinalIgnoreCase);
            if (hi < 0) { Console.WriteLine("  [HTML] !! 未找到 </head>"); return 1; }
            s = s.Insert(hi, SkinBlock(skin));

            // 2b. require.js(data-main=ext) + 自执行脚本 → apploader.js 完整标签之后（body 内）
            //     ★ 修复: 不能用 IndexOf('>') 只看开标签结束——官方 index.html 可能是
            //       <script src="apploader.js" defer></script>（带显式 </script>），
            //       那会把注入内容嵌进 apploader 的 script 体内（HTML 嵌套损坏，插件失效）。
            //       必须匹配 apploader 的完整标签块（含 </script>）再插入，与 amilys 一致。
            int insertAt = -1;
            var ai = s.IndexOf("apploader.js", StringComparison.OrdinalIgnoreCase);
            if (ai >= 0)
            {
                // 匹配完整 <script ...apploader.js...>...</script> 块（显式闭合）
                // 或单标签 <script ...apploader.js...>（无显式闭合，HTML5 隐式）
                var appMatch = Regex.Match(s,
                    "<script[^>]*apploader\\.js[^>]*>\\s*(</script>)?",
                    RegexOptions.IgnoreCase | RegexOptions.Singleline);
                if (appMatch.Success)
                {
                    // 若匹配到显式 </script>，插到其后；否则插到单标签后（隐式闭合到 </body>）
                    insertAt = appMatch.Index + appMatch.Length;
                }
            }
            if (insertAt < 0)
            {
                var bi = s.IndexOf("</body>", StringComparison.OrdinalIgnoreCase);
                insertAt = bi >= 0 ? bi : s.Length;   // 兜底 </body> 前
            }
            s = s.Insert(insertAt, DirectScriptsBlock + RequireBlock);

            File.WriteAllText(output, s);

            // ========== 3) 输出诊断 ==========
            Console.WriteLine($"  [HTML] 清洗: 移除皮肤×{removedCrx} + require.js×{removedReq} + 自执行脚本×{mDirect.Count}");
            Console.WriteLine($"  [HTML] 重新注入: 皮肤[{skin}](</head>前) + 自执行脚本+require.js(apploader后,pos={insertAt})");
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