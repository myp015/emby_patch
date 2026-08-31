using System;
using System.IO;
using System.Text.RegularExpressions;

namespace EmbyPatch2
{
    // ===================================================================
    // HTML patch（v5）：前端增强全部直接嵌入 index.html
    //
    // 2026-08-31 v5 变更（方案A 精简版）：
    //   - 删除 emby-crx 全家桶工作流（style.css/common-utils/jquery/md5/config/main.js）
    //   - 删除 ext.sh / ext.js / require.js / extmod 机制
    //   - 前端增强只剩 3 个文件，全部直接 <script> 嵌入 index.html：
    //       1. embyHappy.js            : 破解注册信息注入（localStorage）
    //       2. embyLaunchPotplayer.js  : 外部播放器（Tampermonkey 风格自执行）
    //       3. swiper_v2/home-swiper.js: 首页海报轮播（IIFE 自执行）
    //   - 三者都依赖 Emby 全局 require/apploader 环境 → 统一插到 apploader.js 之后
    //
    // 用法: EmbyPatch2 html <输入index.html> <输出index.html>
    // ===================================================================
    internal static class HtmlPatcher
    {
        // 全部前端增强（顺序：注册注入 → 外部播放器 → 海报轮播）
        private const string EnhanceBlock =
            "<script src=\"embyHappy.js\"></script>\n" +
            "<script src=\"embyLaunchPotplayer.js\"></script>\n" +
            "<script src=\"swiper_v2/home-swiper.js\"></script>\n";

        public static int Patch(string input, string output)
        {
            var s = File.ReadAllText(input);

            // ========== 1) 清洗旧注入（任意顺序下的旧块都移除）==========
            int removed = 0;
            // 移除旧皮肤（emby-crx 全家桶 + home-swiper.js，任意顺序）
            var oldRegex = new Regex(
                "<link[^>]*emby-crx/style\\.css[^>]*>\\s*" +
                "|<script[^>]*src=\"emby-crx/[^\"]*\"[^>]*>\\s*" +
                "|<script[^>]*src=\"swiper_v2/home-swiper\\.js\"[^>]*>\\s*" +
                "|<script[^>]*src=\"embyHappy\\.js\"[^>]*>\\s*" +
                "|<script[^>]*src=\"embyLaunchPotplayer\\.js\"[^>]*>\\s*",
                RegexOptions.IgnoreCase | RegexOptions.Singleline);
            removed += oldRegex.Matches(s).Count;
            s = oldRegex.Replace(s, "");

            // 移除旧 require.js data-main=ext 注入行（extmod 机制已废弃）
            var reqRegex = new Regex(
                "<script[^>]*data-main=\"ext\"[^>]*src=\"require\\.js\"[^>]*>\\s*" +
                "|<script[^>]*src=\"require\\.js\"[^>]*data-main=\"ext\"[^>]*>\\s*",
                RegexOptions.IgnoreCase | RegexOptions.Singleline);
            removed += reqRegex.Matches(s).Count;
            s = reqRegex.Replace(s, "");

            // ========== 2) 注入前端增强 → apploader.js 完整标签之后（body 内） ==========
            int insertAt = -1;
            var ai = s.IndexOf("apploader.js", StringComparison.OrdinalIgnoreCase);
            if (ai >= 0)
            {
                var appMatch = Regex.Match(s,
                    "<script[^>]*apploader\\.js[^>]*>\\s*(</script>)?",
                    RegexOptions.IgnoreCase | RegexOptions.Singleline);
                if (appMatch.Success)
                {
                    insertAt = appMatch.Index + appMatch.Length;
                }
            }
            if (insertAt < 0)
            {
                var bi = s.IndexOf("</body>", StringComparison.OrdinalIgnoreCase);
                insertAt = bi >= 0 ? bi : s.Length;   // 兜底 </body> 前
            }
            s = s.Insert(insertAt, EnhanceBlock);

            File.WriteAllText(output, s);

            // ========== 3) 输出诊断 ==========
            Console.WriteLine($"  [HTML] 清洗: 移除旧注入×{removed}");
            Console.WriteLine($"  [HTML] 注入前端增强(embyHappy+embyLaunchPotplayer+home-swiper) → apploader后,pos={insertAt}");
            var scripts = Regex.Matches(s, "<script[^>]*src=\"([^\"]*)\"[^>]*>");
            Console.Write("  [HTML] 最终 script 顺序:");
            foreach (System.Text.RegularExpressions.Match m in scripts)
                Console.Write($" {m.Groups[1].Value.Split('/')[^1]}");
            Console.WriteLine();
            return 0;
        }
    }
}
