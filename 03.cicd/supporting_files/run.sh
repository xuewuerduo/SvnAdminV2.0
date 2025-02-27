#!/bin/bash
#
# Prepare our container for initial boot.


#######################################
# Use sed to replace cli php.ini values for a given PHP version.
# Globals:
#   PHP_TIMEZONE
# Arguments:
#   $1 - PHP version i.e. 5.6, 7.3 etc.
# Returns:
#   None
#######################################
#function replace_cli_php_ini_values () {
#    echo "Replacing CLI php.ini values"
#    sed -i  "s/;date.timezone =/date.timezone = Asia\/Shanghai/g" /etc/php/$1/cli/php.ini
#}
#if [ -e /etc/php/5.6/cli/php.ini ]; then replace_cli_php_ini_values "5.6"; fi
#if [ -e /etc/php/$PHP_VERSION/cli/php.ini ]; then replace_cli_php_ini_values $PHP_VERSION; fi
export APACHE_ROOT=/app

echo "Editing APACHE_RUN_GROUP environment variable"
sed -i "s/export APACHE_RUN_GROUP=www-data/export APACHE_RUN_GROUP=staff/" /etc/apache2/envvars

#if [ -n "$APACHE_ROOT" ];then
#    echo "Linking /var/www/html to the Apache root"
#    rm -f /var/www/html && ln -s "/app/${APACHE_ROOT}" /var/www/html
#fi



# Listen only on IPv4 addresses
sed -i 's/^Listen .*/Listen 0.0.0.0:80/' /etc/apache2/ports.conf

source /etc/profile


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
chown -R www-data:www-data /run/apache2
source /etc/apache2/envvars
/usr/sbin/apache2
/usr/sbin/php-fpm

while [[ true ]]; do
    sleep 1
done
