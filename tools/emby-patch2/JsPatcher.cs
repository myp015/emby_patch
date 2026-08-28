using System;
using System.IO;

namespace EmbyPatch2
{
    // ===================================================================
    // JS patch 模式：复刻 amilys 前端破解（字符串替换，与 amilys md5 一致）
    // 用法: EmbyPatch2 js <输入JS文件> <输出JS文件>
    //   - connectionmanager.js: validateDevice URL→本地 /?, 缓存365, 伪造成功
    //   - embypremiere.js: getStatus→本地 /, 伪造 Lifetime 响应
    // 由文件名自动识别处理逻辑
    // ===================================================================
    internal static class JsPatcher
    {
        public static int Patch(string input, string output)
        {
            var s = File.ReadAllText(input);
            var name = Path.GetFileName(input);
            var outS = name switch
            {
                "connectionmanager.js" => PatchConnectionManager(s),
                "embypremiere.js" => PatchEmbyPremiere(s),
                "usersettingsbuilder.js" => PatchUserSettingsBuilder(s),
                _ => s
            };
            File.WriteAllText(output, outS);
            Console.WriteLine($"  [JS] {name}: {s.Length} -> {outS.Length} chars");
            return 0;
        }

        static string PatchConnectionManager(string s)
        {
            // 1. validateDevice URL → 本地 /?
            s = s.Replace("https://mb3admin.com/admin/service/registration/validateDevice?", "/?");
            // 2. cacheExpirationDays 用 response 的 → 写死 365
            s = s.Replace("cacheExpirationDays:response.cacheExpirationDays", "cacheExpirationDays:365");
            s = s.Replace("cacheExpirationDays:0", "cacheExpirationDays:365");
            // 3. 失败状态伪造为 200（成功）
            s = s.Replace("(response||{}).status", "200");
            // 4. lastValidDate 失败标记 -1 → Date.now()（永远有效）
            s = s.Replace("lastValidDate:-1", "lastValidDate:Date.now()");
            return s;
        }

        static string PatchEmbyPremiere(string s)
        {
            // 1. getStatus URL → 本地 /
            s = s.Replace("https://mb3admin.com/admin/service/registration/getStatus", "/");
            // 2. getStatus 紧邻的 response.json() → 本地伪造 Lifetime（精确替换整段）
            const string fake = "{\"deviceStatus\": \"0\",\"planType\": \"Lifetime\",\"subscriptions\": {\"home\": \"opve.cn\",\"key\": 433493451}}";
            const string old = "fetch(\"/\",{method:\"POST\",body:key,headers:{\"Content-Type\":\"application/x-www-form-urlencoded\"}}).then(function(response){return response.json()})";
            var newS = "fetch(\"/\",{method:\"POST\",body:key,headers:{\"Content-Type\":\"application/x-www-form-urlencoded\"}}).then(function(response){return " + fake + "})";
            s = s.Replace(old, newS);
            return s;
        }

        // 侧边栏默认关闭：drawerStyle/settingsDrawerStyle 默认值 docked → closed
        // （源码级修改，首次访问即关闭；用户后续操作仍覆盖记录值）
        static string PatchUserSettingsBuilder(string s)
        {
            s = s.Replace("get(\"drawerstyle\",!1)||\"docked\"", "get(\"drawerstyle\",!1)||\"closed\"");
            s = s.Replace("get(\"settingsdrawerstyle\",!1)||\"docked\"", "get(\"settingsdrawerstyle\",!1)||\"closed\"");
            return s;
        }
    }
}