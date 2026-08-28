const extmod=[]

require(['embyHappy'], function () {
    // 这里的匿名函数已经被调用了
});

require(extmod, function () {
    // 这里的匿名函数已经被调用了
    console.log("扩展插件已经被调用：", extmod.join(', '));
});