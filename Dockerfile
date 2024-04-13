#FROM ubuntu:24.04
FROM php:8.2-fpm

LABEL MAINTAINER = "www.witersen.com 2023-07-23"

# 时间同步
ENV TZ=Asia/Shanghai \
    DEBIAN_FRONTEND=noninteractive

RUN ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone
#
#RUN apt install -y git
#RUN git clone https://gitee.com/witersen/SvnAdminV2.0.git
#RUN mv /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.bak
#RUN echo 'deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware' >/etc/apt/sources.list.d/tun.tsinghua.list
#RUN echo 'deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware' >>/etc/apt/sources.list.d/tun.tsinghua.list
#RUN echo " " >>/etc/apt/sources.list.d/tun.tsinghua.list
#RUN echo 'deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware' >>/etc/apt/sources.list.d/tun.tsinghua.list
#RUN echo 'deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware' >>/etc/apt/sources.list.d/tun.tsinghua.list
#RUN echo " " >>/etc/apt/sources.list.d/tun.tsinghua.list
#RUN echo 'deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware' >>/etc/apt/sources.list.d/tun.tsinghua.list
#RUN echo 'deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware' >>/etc/apt/sources.list.d/tun.tsinghua.list
#RUN echo " " >>/etc/apt/sources.list.d/tun.tsinghua.list
#RUN echo 'deb https://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware' >>/etc/apt/sources.list.d/tun.tsinghua.list
#RUN echo 'deb-src https://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware' >>/etc/apt/sources.list.d/tun.tsinghua.list
#RUN apt update -y && apt upgrade -y
#RUN apt install -y subversion
#RUN apt install -y subversion-tools
#RUN apt install -y libapache2-mod-svn libsvn-dev openssl zip unzip wget vim which libsasl2-2 sasl2-bin libsasl2-modules cron at apache2 libfreetype-dev libjpeg62-turbo-dev libpng-dev



#RUN /usr/local/bin/docker-php-ext-configure gd --with-freetype --with-jpeg
#RUN /usr/local/bin/docker-php-ext-configure gd
#
#RUN /usr/local/bin/docker-php-ext-configure bcmath
#RUN /usr/local/bin/docker-php-ext-install bcmath
#
#
#RUN /usr/local/bin/docker-php-ext-configure ldap
#RUN /usr/local/bin/docker-php-ext-install ldap
#
#
#RUN /usr/local/bin/docker-php-ext-configure pdo_mysql
#RUN /usr/local/bin/docker-php-ext-install pdo_mysql






# 配置文件
ADD ./03.cicd/svnadmin_docker/data/ /home/svnadmin/
RUN ls /home/svnadmin/
RUN cd /home/svnadmin/ \
    && mkdir -p backup \
    && mkdir -p crond \
    && mkdir -p rep \
    && mkdir -p temp \
    && mkdir -p templete/initStruct/01/branches \
    && mkdir -p templete/initStruct/01/tags \
    && mkdir -p templete/initStruct/01/trunk 
#RUN chown -R apache:apache /home/svnadmin/ && mkdir -p /run/php-fpm/
RUN chown -R www-data:www-data /home/svnadmin/ && mkdir -p /run/php-fpm/


# 前端处理

RUN curl -L -o /usr/local/node-v14.18.2-linux-x64.tar.gz https://registry.npmmirror.com/-/binary/node/latest-v14.x/node-v14.18.2-linux-x64.tar.gz \
    && tar -xf /usr/local/node-v14.18.2-linux-x64.tar.gz -C /usr/local/ \
    && ln -s /usr/local/node-v14.18.2-linux-x64/bin/node /usr/local/bin/node \
    && ln -s /usr/local/node-v14.18.2-linux-x64/bin/npm /usr/local/bin/npm \
    && npm config set registry https://registry.npm.taobao.org \
    
RUN ls
#RUN ls -la SvnAdminV2.0/
RUN mkdir /root/svnadmin_web 
ADD ./01.web/package.json /root/svnadmin_web/
RUN ls
#COPY 01.web/package-lock.json /root/svnadmin_web/
#RUN ls -la /root/svnadmin_web/
RUN cd /root/svnadmin_web 
RUN cat package.json 
RUN npm install

COPY 01.web/ /root/svnadmin_web/

RUN cd /root/svnadmin_web/ \
    && npm run build \
    && mv dist/* /var/www/html/ \
    && rm -rf /root/svnadmin_web \
    && rm -rf /usr/local/node-v14.18.2-linux-x64*

# 后端处理
ADD 02.php/ /var/www/html/

ADD 03.cicd/svnadmin_docker/start.sh /root/start.sh
RUN chmod +x /root/start.sh

EXPOSE 80
EXPOSE 443
EXPOSE 3690

CMD ["/root/start.sh"]
