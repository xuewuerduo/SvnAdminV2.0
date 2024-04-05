# This Dockerfile is intended only for TESTING.
# Docker镜像打包

#ARG THIS_ARCH=arm64
ARG INSTALL_PHPEXT=true
FROM php:8.2-apache
ENV DEBIAN_FRONTEND noninteractive

#克隆仓库
RUN git clone https://github.com/xuewuerduo/SvnAdminV2.0.git /tmp/svnadmin2


# 时间同步
ENV TZ=Asia/Shanghai \
    DEBIAN_FRONTEND=noninteractive

RUN ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone

# 编码修改
RUN localedef -c -i en_US -f UTF-8 C.UTF-8 \
    && echo 'LANG="C.UTF-8"' >> /etc/sysconfig/i18n \
    && echo 'LC_ALL="C.UTF-8"' >> /etc/sysconfig/i18n \
    && echo 'export LANG="C.UTF-8"' >> /etc/profile \
    && echo 'export LC_ALL="C.UTF-8"' >> /etc/profile


# 开启php扩展安装
RUN apt-get update && apt-get install -y \
    cyrus-sasl \
    cyrus-sasl-lib \
    cyrus-sasl-plain \
    subversion \
    subversion-tools \
    && apt clean all

#安装并启用PHP扩展
RUN docker-php-ext-configure php-common && \
    docker-php-ext-install -j$(nproc) php-common && \
    docker-php-ext-enable php-common

RUN docker-php-ext-configure php-cli && \
    docker-php-ext-install -j$(nproc) php-cli && \
    docker-php-ext-enable php-cli
    
RUN docker-php-ext-configure php-fpm && \
    docker-php-ext-install -j$(nproc) php-fpm && \
    docker-php-ext-enable php-fpm
    
RUN docker-php-ext-configure php-mysqlnd && \
    docker-php-ext-install -j$(nproc) php-mysqlnd && \
    docker-php-ext-enable php-mysqlnd
    
RUN docker-php-ext-configure php-mysql && \
    docker-php-ext-install -j$(nproc) php-mysql && \
    docker-php-ext-enable php-mysql
    
RUN docker-php-ext-configure php-pdo && \
    docker-php-ext-install -j$(nproc) php-pdo && \
    docker-php-ext-enable php-pdo
    
RUN docker-php-ext-configure php-process && \
    docker-php-ext-install -j$(nproc) php-process && \
    docker-php-ext-enable php-process
    
RUN docker-php-ext-configure php-json && \
    docker-php-ext-install -j$(nproc) php-json && \
    docker-php-ext-enable php-json
    
RUN docker-php-ext-configure php-gd && \
    docker-php-ext-install -j$(nproc) php-gd && \
    docker-php-ext-enable php-gd   
    
RUN docker-php-ext-configure php-bcmath && \
    docker-php-ext-install -j$(nproc) php-bcmath && \
    docker-php-ext-enable php-bcmath
    
RUN docker-php-ext-configure php-ldap && \
    docker-php-ext-install -j$(nproc) php-ldap && \
    docker-php-ext-enable php-ldap
    
RUN docker-php-ext-configure php-mbstring && \
    docker-php-ext-install -j$(nproc) php-mbstring && \
    docker-php-ext-enable php-mbstring

RUN docker-php-ext-configure php-sqllite && \
    docker-php-ext-install -j$(nproc) php-sqllite && \
    docker-php-ext-enable php-sqllite

# 安装web服务器（推荐 apache 可使用http协议检出）
RUN apt-get install -y \
    mod_dav_svn \
    mod_ldap




# 关闭PHP彩蛋
RUN sed -i 's/expose_php = On/expose_php = Off/g' /etc/php.ini 

# 配置文件
ADD /tmp/svnadmin2/03.cicd/svnadmin_docker/data/ /home/svnadmin/
RUN cd /home/svnadmin/ \
    && mkdir -p backup \
    && mkdir -p crond \
    && mkdir -p rep \
    && mkdir -p temp \
    && mkdir -p templete/initStruct/01/branches \
    && mkdir -p templete/initStruct/01/tags \
    && mkdir -p templete/initStruct/01/trunk 
RUN chown -R apache:apache /home/svnadmin/ && mkdir -p /run/php-fpm/


# 前端处理

RUN curl -L -o /usr/local/node-v14.18.2-linux-x64.tar.gz https://registry.npmmirror.com/-/binary/node/latest-v14.x/node-v14.18.2-linux-x64.tar.gz \
    && tar -xvf /usr/local/node-v14.18.2-linux-x64.tar.gz -C /usr/local/ \
    && ln -s /usr/local/node-v14.18.2-linux-x64/bin/node /usr/local/bin/node \
    && ln -s /usr/local/node-v14.18.2-linux-x64/bin/npm /usr/local/bin/npm \
    && npm config set registry https://registry.npm.taobao.org \


RUN mkdir /root/svnadmin_web 

COPY /tmp/svnadmin2/01.web/package.json /root/svnadmin_web/
COPY /tmp/svnadmin2/01.web/package-lock.json /root/svnadmin_web/
RUN cd /root/svnadmin_web && npm install

COPY /tmp/svnadmin2/01.web/ /root/svnadmin_web/

RUN cd /root/svnadmin_web/ \
    && npm run build \
    && mv dist/* /var/www/html/ \
    && rm -rf /root/svnadmin_web \
    && rm -rf /usr/local/node-v14.18.2-linux-x64*

# 后端处理
ADD /tmp/svnadmin2/02.php/ /var/www/html/

ADD /tmp/svnadmin2/03.cicd/svnadmin_docker/start.sh /root/start.sh
RUN chmod +x /root/start.sh

EXPOSE 80
EXPOSE 443
EXPOSE 3690

CMD ["/root/start.sh"]
