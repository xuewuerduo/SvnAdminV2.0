FROM phusion/baseimage:focal-1.1.0
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

#ARG PHP_VERSION
#ENV PHP_VERSION=$PHP_VERSION

# Tweaks to give Apache/PHP write permissions to the app
RUN usermod -u ${BOOT2DOCKER_ID} www-data && \
    usermod -G staff www-data && \
    groupmod -g $(($BOOT2DOCKER_GID + 10000)) $(getent group $BOOT2DOCKER_GID | cut -d: -f1) && \
    groupmod -g ${BOOT2DOCKER_GID} staff

# 安装 packages
ENV DEBIAN_FRONTEND noninteractive
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash -
RUN LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php && \
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4F4EA0AAE5267A6C && \
  apt-get update && \
  apt-get -y upgrade && \
  apt-get -y install postfix python3-setuptools wget git apache2 php${PHP_VERSION}-xdebug libapache2-mod-php${PHP_VERSION} php${PHP_VERSION}-ldap php${PHP_VERSION}-sqlite3 php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql pwgen php${PHP_VERSION}-apcu php${PHP_VERSION}-gd php${PHP_VERSION}-xml php${PHP_VERSION}-mbstring zip unzip php${PHP_VERSION}-zip curl php${PHP_VERSION}-curl && \
  apt-get -y install subversion libapache2-mod-svn subversion-tools libsvn-dev nodejs && \
  apt-get -y install libsasl2-modules-gssapi-mit at sasl2-bin && \
  apt-get -y autoremove && \
  apt-get -y clean && \
  echo "ServerName localhost" >> /etc/apache2/apache2.conf

# 安装 supervisor 4
RUN curl -L https://pypi.io/packages/source/s/supervisor/supervisor-${SUPERVISOR_VERSION}.tar.gz | tar xvz && \
  cd supervisor-${SUPERVISOR_VERSION}/ && \
  python3 setup.py install

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

# Configure /app folder with sample app
RUN mkdir -p /app && rm -fr /var/www/html && ln -s /app /var/www/html
#ADD app/ /app
RUN ln -s /usr/sbin/php-fpm8.0 /usr/sbin/php-fpm \
    && mkdir -p /run/php

# 配置文件

RUN mkdir /root/svnadmin_web
ADD 01.web/ /root/svnadmin_web/
ADD 03.cicd/svnadmin_docker/data/ /home/svnadmin/
RUN cd /home/svnadmin/ && \
    mkdir -p backup crond rep temp templete/initStruct/01/branches templete/initStruct/01/tags templete/initStruct/01/trunk
RUN chown -R www-data:www-data /home/svnadmin/ && \
    mkdir -p /run/php-fpm/


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

EXPOSE 80
EXPOSE 443
EXPOSE 3690

CMD ["/root/run.sh 8.0"]
