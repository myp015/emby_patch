# 容器运行时触发链验证

  ✅ 容器启动 
  ❌ ext.sh 已创建到 /config/config/ ls: /config/config/ext.sh: No such file or directory
  ❌ ext.js 存在且 extmod 已注入 const extmod=[]  require(['embyHappy'], function () {     // 这里的匿名函数已经被调用了 });  require(extmod, function () {     // 这里的匿名函数已经被调用了     console.log("扩展插件已经被调用：",
  ✅ config.js parentId 注入 3:		//媒体库id，用逗号分隔。进入媒体库后url里的parentId
4:		//this.parentId = "5,21463";
5:                this.parentId = "";
  ✅ 顺序 emby-crx < apploader < require.js (crx=0 app=1 req=2)
  ✅ mb.lic + hosts mb3admin 指向 -rw-r--r--    1 bin      bin             22 Aug 28 10:01 /config/config/mb.lic | 199.255.98.60 mb3admin.com
总结: ✅4 / ❌2
