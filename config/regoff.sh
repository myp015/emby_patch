#!/bin/sh

# ===================================================================
# 注册关闭（复刻 amilys /etc/regoff.sh，修复：无条件写 mb.lic）
# 由 /etc/services.d/emby-server/run 每次启动时调用
# 作用：
#   1) 写 /config/config/mb.lic（伪造 Emby Premiere 授权文件）
#   2) /etc/hosts 添加伪 mb3admin（199.255.98.60）→ 注册验证指向伪服务器
#   3) 写插件注册配置（已注册/长期有效）
# ===================================================================

# 定义配置文件目录
CONFIG_DIR='/config/plugins/configurations'
LICENSE_DIR='/config/config'

# 创建目录（幂等）
mkdir -p "$CONFIG_DIR"
mkdir -p "$LICENSE_DIR"

# ★ 无条件写 mb.lic（修复：之前 if [ ! -d ] 在目录已存在时跳过 → mb.lic 缺失）
echo '疯狂星期四V我50' > "$LICENSE_DIR/mb.lic"

# 注册配置（base64：{"registered":true,"expDate":"2030-...","isTrial":false,"isValid":true}）
CONFIG_CONTENT='eyJyZWdpc3RlcmVkIjp0cnVlLCJleHBEYXRlIjoiMjAzMC0wMS0wMVQwMDowMDowMC4wMDAwMDAwWiIsImxhc3RDaGVja2VkIjoiMjAyMy0wOC0yOVQxMzoxODoxOS44NTk5NzA3WiIsImlzVHJpYWwiOmZhbHNlLCJpc1ZhbGlkIjp0cnVlfQ=='
echo "$CONFIG_CONTENT" > "$CONFIG_DIR/57556c0b1664038946abc87649b9efd8"

# hosts 指向伪 mb3admin（199.255.98.60 mb3admin.com）
TARGET_ENTRY="199.255.98.60 mb3admin.com"
if ! grep -qF "$TARGET_ENTRY" /etc/hosts; then
    echo "$TARGET_ENTRY" >> /etc/hosts
fi

exit 0