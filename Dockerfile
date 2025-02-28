#FROM phusion/baseimage:focal-1.1.0
FROM ubuntu:24.04

MAINTAINER xuewuerduo <xuewuerduo@163.com>
ENV REFRESHED_AT 2025-02-26
LABEL MAINTAINER = "www.witersen.com 2023-07-23"


# 时间同步
ENV TZ=Asia/Shanghai \
    DEBIAN_FRONTEND=noninteractive

RUN ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone

ENV DOCKER_USER_ID 501
ENV DOCKER_USER_GID 20

ENV BOOT2DOCKER_ID 1000
ENV BOOT2DOCKER_GID 50

ENV SUPERVISOR_VERSION=4.2.2
ENV PHP_VERSION=8.0

#Environment variables to configure php
ENV PHP_UPLOAD_MAX_FILESIZE 1024M
ENV PHP_POST_MAX_SIZE 1024M



# 安装 packages
ENV DEBIAN_FRONTEND noninteractive

#安装基础工具
RUN apt install -y software-properties-common curl

RUN curl -sL https://deb.nodesource.com/setup_14.x | bash -
RUN LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php && \
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4F4EA0AAE5267A6C && \
  add-apt-repository ppa:ondrej/apache2 -y && \
  apt-get update && \
  apt-get -y upgrade && \
  apt-get -y install postfix python3-setuptools wget git apache2 php${PHP_VERSION}-xdebug libapache2-mod-php${PHP_VERSION} php${PHP_VERSION}-ldap php${PHP_VERSION}-sqlite3 php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql pwgen php${PHP_VERSION}-apcu php${PHP_VERSION}-gd php${PHP_VERSION}-xml php${PHP_VERSION}-mbstring zip unzip php${PHP_VERSION}-zip curl php${PHP_VERSION}-curl && \
  apt-get -y install subversion libapache2-mod-svn subversion-tools libsvn-dev nodejs passwd && \
  apt-get -y install libsasl2-modules-gssapi-mit at sasl2-bin uuid-dev uuid-runtime && \
  apt-get -y autoremove && \
  apt-get -y clean && \
  echo "ServerName localhost" >> /etc/apache2/apache2.conf


# Tweaks to give Apache/PHP write permissions to the app
#RUN usermod -u ${BOOT2DOCKER_ID} www-data && \
#    usermod -G staff www-data && \
#    groupmod -g $(($BOOT2DOCKER_GID + 10000)) $(getent group $BOOT2DOCKER_GID | cut -d: -f1) && \
#    groupmod -g ${BOOT2DOCKER_GID} staff

## 安装 supervisor 4
#RUN curl -L https://pypi.io/packages/source/s/supervisor/supervisor-${SUPERVISOR_VERSION}.tar.gz | tar xvz && \
#  cd supervisor-${SUPERVISOR_VERSION}/ && \
#  python3 setup.py install

# Add image configuration and scripts
ADD 03.cicd/supporting_files/start-apache2.sh /start-apache2.sh
ADD 03.cicd/supporting_files/run.sh /run.sh
RUN chmod 755 /*.sh
ADD 03.cicd/supporting_files/supervisord-apache2.conf /etc/supervisor/conf.d/supervisord-apache2.conf
ADD 03.cicd/supporting_files/supervisord.conf /etc/supervisor/supervisord.conf


# 安装 composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
    php composer-setup.php && \
    php -r "unlink('composer-setup.php');" && \
    mv composer.phar /usr/local/bin/composer


# config to enable .htaccess
ADD 03.cicd/supporting_files/apache_default /etc/apache2/sites-available/000-default.conf
RUN a2enmod rewrite


#ADD app/ /app
RUN ln -s /usr/sbin/php-fpm8.0 /usr/sbin/php-fpm \
    && mkdir -p /run/php && \
    mkdir -p /app && rm -fr /var/www/html &&  \
    ln -s /app /var/www/html


# 配置文件

RUN mkdir /root/svnadmin_web
ADD 01.web/ /root/svnadmin_web/
ADD 03.cicd/svnadmin_docker/data/ /home/svnadmin/
RUN cd /home/svnadmin/ && \
    mkdir -p backup crond rep temp templete/initStruct/01/branches templete/initStruct/01/tags templete/initStruct/01/trunk
RUN chown -R www-data:www-data /home/svnadmin/ && \
    mkdir -p /run/php-fpm/

RUN sed -i  "s/;date.timezone =/date.timezone = Asia\/Shanghai/g" /etc/php/${PHP_VERSION}/cli/php.ini

# 前端处理
ADD 01.web/package.json /root/svnadmin_web/package.json
RUN cd /root/svnadmin_web && \
    npm install && \
    npm run build && \
    mv dist/* /app \
    && rm -rf /root/svnadmin_web


# 后端处理
ADD 02.php/ /app
ADD 03.cicd/supporting_files/run.sh /root/run.sh
RUN chmod +x /root/run.sh


#修复httpd切换为apache2导致的程序问题
RUN sed -i 's/LoadModule/#LoadModule/g' /app/templete/apache/*.conf
RUN ln -s /usr/sbin/apache2 /usr/sbin/httpd
RUN mkdir -p /etc/httpd/conf.d && \
    touch /etc/httpd/conf.d/subversion.conf && \
    mv /etc/apache2/mods-enabled/dav_svn.conf /etc/apache2/mods-enabled/dav_svn.conf.bak && \
    ln -s /etc/httpd/conf.d/subversion.conf /etc/apache2/mods-enabled/dav_svn.conf

RUN echo 'export APACHE_RUN_USER=www-data' >> /etc/profile
RUN echo 'export APACHE_RUN_GROUP=staff' >> /etc/profile
RUN echo 'export APACHE_PID_FILE=/var/run/apache2/apache2.pid' >> /etc/profile
RUN echo 'export APACHE_RUN_DIR=/var/run/apache2' >> /etc/profile
RUN echo 'export APACHE_LOCK_DIR=/var/lock/apache2' >> /etc/profile
RUN echo 'export APACHE_LOG_DIR=/var/log/apache2' >> /etc/profile
RUN echo 'export LANG=C' >> /etc/profile
RUN echo 'export LANG' >> /etc/profile

#信息统计页错误处理
ADD 03.cicd/supporting_files/Statistics.php /app/app/service/Statistics.php

EXPOSE 80
EXPOSE 443
EXPOSE 3690

CMD ["/root/run.sh"]
