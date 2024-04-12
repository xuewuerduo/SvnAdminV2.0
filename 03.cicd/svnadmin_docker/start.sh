#!/bin/bash

source /etc/profile

/usr/local/sbin/php-fpm

/usr/bin/svnserve --daemon --pid-file=/home/svnadmin/svnserve.pid -r '/home/svnadmin/rep/' --config-file '/home/svnadmin/svnserve.conf' --log-file '/home/svnadmin/logs/svnserve.log' --listen-port 3690 --listen-host 0.0.0.0

spid=$(uuidgen)

/usr/sbin/saslauthd -a 'ldap' -O "$spid" -O '/home/svnadmin/sasl/ldap/saslauthd.conf'

ps aux | grep -v grep | grep "$spid" | awk 'NR==1' | awk '{print $2}' > '/home/svnadmin/sasl/saslauthd.pid'
chmod 777 /home/svnadmin/sasl/saslauthd.pid

/usr/sbin/cron

/usr/sbin/atd

/usr/bin/php /var/www/html/server/svnadmind.php start &

rm -rf /run/apache2
mkdir -p /run/apache2
#chown -R apache:apache /run/httpd
chown -R www-data:www-data /run/httpd
/usr/sbin/apache2

while [[ true ]]; do
    sleep 1
done
