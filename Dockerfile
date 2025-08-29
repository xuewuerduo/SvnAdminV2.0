# 第一阶段：前端构建阶段
FROM node:18.20.8-bookworm AS builder

# 配置环境变量
ENV TZ=Asia/Shanghai

WORKDIR /home

ADD 01.web/ /home/html
WORKDIR /home/html
# 复制前端源码并构建

RUN npm install --registry=https://registry.npmmirror.com; \
    npm run build; \
    # 验证构建结果 \
    if [ ! -d "dist" ]; then echo "构建失败"; exit 1; fi;

# 第二阶段：最终运行环境阶段
FROM rockylinux/rockylinux:9

# 配置环境变量
ENV TZ=Asia/Shanghai \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# 复制前端构建产物（从第一阶段）
COPY --from=builder /home/01.web/dist/ /var/www/html/

# 复制其他应用文件（从第一阶段）
COPY 02.php /var/www/html/

# 复制其他应用文件
COPY 03.template/ /templete/
COPY favicon.ico /var/www/html/favicon.ico

# 复制启动脚本
COPY Start.sh /home/Start.sh

# 修改SQLite数据库登录不要验证码
COPY svnadmin.db /templete/svnadmin.db

# 安装系统依赖和运行环境
RUN set -eux \
    # 配置时区 \
    echo "${TZ}" > /etc/timezone; \
    # dnf install -y https://rpms.remirepo.net/enterprise/remi-release-10.rpm; \
    dnf install -y https://mirrors.aliyun.com/remi/enterprise/remi-release-9.rpm; \
    dnf module enable -y php:remi-8.4; \
    sed -e 's|^mirrorlist=|#mirrorlist=|g' \
       -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.aliyun.com/rockylinux|g' \
       -i.bak \
       /etc/yum.repos.d/rocky*.repo; \
    # 安装运行时依赖 \
    dnf install -y  \
        --setopt=install_weak_deps=False --nodocs \
        httpd \
        mod_dav_svn \
        mod_ldap \
        subversion \
        subversion-tools \
        php \
        php-common \
        php-cli \
        php-fpm \
        php-json \
        php-mysqlnd \
        php-pdo \
        php-process \
        php-gd \
        php-bcmath \
        php-ldap \
        php-mbstring \
        cyrus-sasl \
        cyrus-sasl-lib \
        cyrus-sasl-plain \
        cronie \
        at \
        procps; \
    # 清理安装缓存 \
    rm -rf /var/cache/dnf; \
    dnf autoremove -y; \
    dnf clean all; \
    rm -rf \
            /var/cache/dnf \
            /etc/yum.repos.d/rocky*.repo.bak \
            /opt /mnt /usr/games /usr/share/man /usr/share/doc \
            /tmp/* /var/tmp/*; \
    # 解决启动时的域名警告问题 \
    echo "ServerName localhost" >> /etc/httpd/conf/httpd.conf; \
    mkdir -p /run/php-fpm/; \
    # PHP安全配置 \
    sed -i 's/expose_php = On/expose_php = Off/g' /etc/php.ini; \
    sed -i 's/listen.acl_users = apache,nginx/listen.acl_users = apache/g' /etc/php-fpm.d/www.conf; \
    chown -R apache:apache /var/www/html; \
    # 赋予启动脚本执行权限 \
    chmod +x /home/Start.sh

# USER apache
WORKDIR /home/svnadmin

# 暴露服务端口
EXPOSE 80
EXPOSE 443
EXPOSE 3690

# 启动服务
CMD ["/home/Start.sh"]
