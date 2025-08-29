#!/bin/bash

# 保存当前的set选项
current_set=$(set +o)
# 关闭未定义变量检查
set +u
# 加载环境变量
. /etc/profile
# 恢复之前的set选项
eval "$current_set"
# 定义常量变量，提高可维护性
SVNADMIN_DIR="/home/svnadmin"
TEMPLETE_DIR="/templete"
RUN_HTTPD_DIR="/run/httpd"

# 加载环境变量
. /etc/profile

# 函数：打印信息
info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1"
}

# 函数：打印错误并退出
error_exit() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    exit 1
}

# 检查并初始化目录结构
info "检查目录结构..."
if [ -z "$(ls -A "$SVNADMIN_DIR" 2>/dev/null)" ]; then
    info "检测到$SVNADMIN_DIR目录为空，正在从$TEMPLETE_DIR复制文件..."

    # 创建目录结构（--parents确保父目录存在）
    mkdir -p \
        "$SVNADMIN_DIR"/{backup,crond,rep,temp,logs,templete/initStruct/01/{branches,tags,trunk}} \
        "$SVNADMIN_DIR/sasl/ldap" \
        || error_exit "创建目录结构失败"

    # 复制模板文件
    cp -r "$TEMPLETE_DIR"/* "$SVNADMIN_DIR/" || error_exit "复制模板文件失败"

else
    info "$SVNADMIN_DIR目录不为空，跳过文件复制"
fi

# 设置权限（合并操作，减少重复执行）
info "设置目录权限..."
chown -R apache:apache \
    "$SVNADMIN_DIR" \
    || error_exit "设置权限失败"

# 启动PHP-FPM
info "启动php-fpm..."
/usr/sbin/php-fpm || error_exit "php-fpm启动失败"

# 启动SVN服务
info "启动svnserve..."
/usr/bin/svnserve --daemon \
    --pid-file="$SVNADMIN_DIR/svnserve.pid" \
    -r "$SVNADMIN_DIR/rep/" \
    --config-file "$SVNADMIN_DIR/svnserve.conf" \
    --log-file "$SVNADMIN_DIR/logs/svnserve.log" \
    --listen-port 3690 \
    --listen-host 0.0.0.0 \
    || error_exit "svnserve启动失败"

# 启动SASL认证服务
info "启动saslauthd..."
spid=$(uuidgen)
/usr/sbin/saslauthd -a 'ldap' \
    -O "$spid" \
    -O "$SVNADMIN_DIR/sasl/ldap/saslauthd.conf" \
    || error_exit "saslauthd启动失败"

# 获取saslauthd进程PID（优化命令链，减少管道使用）
sasl_pid=$(ps aux | grep -v grep | grep -m 1 "$spid" | awk '{print $2}')
if [ -z "$sasl_pid" ]; then
    error_exit "无法获取saslauthd进程PID"
fi
echo "$sasl_pid" > "$SVNADMIN_DIR/sasl/saslauthd.pid"
chmod 644 "$SVNADMIN_DIR/sasl/saslauthd.pid"  # 使用更安全的权限，而非777

# 启动定时任务服务
info "启动crond和atd..."
/usr/sbin/crond || error_exit "crond启动失败"
/usr/sbin/atd || error_exit "atd启动失败"

# 启动svnadmind后台服务
info "启动svnadmind服务..."
/usr/bin/php /var/www/html/server/svnadmind.php start &
svnadmind_pid=$!

# 启动HTTP服务（优化目录处理，避免不必要的删除）
info "启动httpd..."
mkdir -p "$RUN_HTTPD_DIR"
    chown -R apache:apache "$RUN_HTTPD_DIR"
/usr/sbin/httpd || error_exit "httpd启动失败"

info "所有服务启动完成，进入监控模式..."

# 监控子进程，确保容器持续运行且能感知子进程退出
wait "$svnadmind_pid"  # 等待后台启动的svnadmind进程