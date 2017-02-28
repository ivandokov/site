#!/usr/bin/env bash

function askForDomain {
    DOMAIN="$1"
    while true; do
        if [ -z "${DOMAIN}" ]; then
            read -p "Website domain: " DOMAIN
        elif ! echo "${DOMAIN}" | grep -qP '(?=^.{5,254}$)(^(?:(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)'; then
            echo "This is not a valid domain name"
            read -p "Website domain: " DOMAIN
        else
            break
        fi
    done

    if [[ "${#DOMAIN}" -gt 32 ]]; then
        echo "This domain name is too long. Max length 32 symbols"
        exit 2
    fi
}

case $1 in
    create)
        askForDomain $2

        SITEROOT=/var/www/${DOMAIN}
        WEBROOT=/var/www/${DOMAIN}/www/public
        FPM_SOCKET=/var/run/php/${DOMAIN}.sock
        PHP_POOL=/etc/php/7.1/fpm/pool.d/${DOMAIN}.conf

        if ! getent passwd ${DOMAIN} > /dev/null; then
            echo "Creating system user ${DOMAIN}"
            sudo useradd -s /bin/bash -r -d "${SITEROOT}" -M "${DOMAIN}"
        fi

        if [ -d ${SITEROOT} ]; then
            echo "Site root directory already exists"
        else
            echo "Creating website root directory at ${SITEROOT}"
            sudo mkdir -p ${SITEROOT}/logs
            sudo mkdir -p ${SITEROOT}/www/public
            echo "Hello, World!" | sudo tee ${SITEROOT}/www/public/index.php > /dev/null

            echo "Changing ownership of all site files to ${DOMAIN}:${DOMAIN}"
            sudo chown -R ${DOMAIN}:${DOMAIN} ${SITEROOT}
        fi

        if [ -f /etc/nginx/sites-available/${DOMAIN}.conf ]; then
            echo "Configuration file for nginx already exists"
        else
	        echo "Creating nginx configuration file"
            sudo tee /etc/nginx/sites-available/${DOMAIN}.conf &>/dev/null <<EOF
server {
	server_name  www.${DOMAIN};
	rewrite ^(.*) http://${DOMAIN}\$1 permanent;
}
server {
	listen 80;
	server_name ${DOMAIN};
	root ${WEBROOT};
	index index.html index.php;
	charset utf-8;

	#access_log ${SITEROOT}/logs/nginx-access.log combined;
	access_log /dev/null;
	error_log  ${SITEROOT}/logs/nginx-error.log error;
	error_page 404 /index.php;

	location / {
		try_files \$uri \$uri/ /index.php?\$query_string;
	}

	location = /favicon.ico { access_log /dev/null; log_not_found off; }
	location = /robots.txt  { access_log /dev/null; log_not_found off; }

	location ~ \.php$ {
		fastcgi_pass unix:${FPM_SOCKET};
		fastcgi_index index.php;
		fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
		include fastcgi_params;
	}
}
EOF
        fi

        if [ -f ${PHP_POOL} ]; then
            echo "Configuration file for php-fpm already exists"
        else
	        echo "Creating php-fpm configuration file"
            sudo tee "${PHP_POOL}" &>/dev/null <<EOF
[${DOMAIN}]
user = ${DOMAIN}
group = ${DOMAIN}
listen = ${FPM_SOCKET}
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
;php_flag[display_errors] = off
php_admin_value[error_log] = ${SITE}/logs/php-error.log
php_admin_flag[log_errors] = on
;php_admin_value[memory_limit] = 512M
EOF
	    fi

        if [ ! -L /etc/nginx/sites-enabled/${DOMAIN}.conf ]; then
            echo "Enabled domain ${DOMAIN}"
            sudo ln -s /etc/nginx/sites-available/${DOMAIN}.conf /etc/nginx/sites-enabled/ > /dev/null
        fi

        echo "Restarting services"
        sudo service nginx reload > /dev/null
	    sudo service php7.1-fpm restart > /dev/null
        ;;
    delete)
        askForDomain $2

        read -p "Are you sure you want to DELETE it? [y/n]: " yn

        if [ "${yn}" != "y" ]; then
            exit 0
        fi

        sudo rm /etc/nginx/sites-available/${DOMAIN}.conf
        sudo rm /etc/nginx/sites-enabled/${DOMAIN}.conf
        sudo rm /etc/php/7.1/fpm/pool.d/${DOMAIN}.conf
        echo "Deleted configurations for ${DOMAIN}"
        sudo service nginx reload
        sudo service php7.1-fpm reload

        read -p "Do you want to DELETE site files? [y/n]: " yn
        if [ "${yn}" == "y" ]; then
            echo "Deleting system user and its files"
            sudo userdel -rf ${DOMAIN}
        fi
        ;;
    enable)
        askForDomain $2

        if [ -f /etc/nginx/sites-available/${DOMAIN}.conf ]; then
            sudo ln -s /etc/nginx/sites-available/${DOMAIN}.conf /etc/nginx/sites-enabled/
            sudo service nginx reload
        else
            echo "Cannot find nginx configuration file for ${DOMAIN}"
        fi

        if [ -f /etc/php/7.1/fpm/pool.d/${DOMAIN}.conf.disabled ]; then
            sudo mv /etc/php/7.1/fpm/pool.d/${DOMAIN}.conf.disabled /etc/php/7.1/fpm/pool.d/${DOMAIN}.conf
            sudo service php7.1-fpm reload
        else
            echo "Cannot find php-fpm configuration file for ${DOMAIN}"
        fi
        ;;
    disable)
        askForDomain $2
        if [ -f /etc/nginx/sites-available/${DOMAIN}.conf ]; then
            sudo rm /etc/nginx/sites-enabled/${DOMAIN}.conf
            sudo service nginx reload
        else
            echo "Cannot find nginx configuration file for ${DOMAIN}"
        fi

        if [ -f /etc/php/7.1/fpm/pool.d/${DOMAIN}.conf ]; then
            sudo mv /etc/php/7.1/fpm/pool.d/${DOMAIN}.conf /etc/php/7.1/fpm/pool.d/${DOMAIN}.conf.disabled
            sudo service php7.1-fpm reload
        else
            echo "Cannot find php-fpm configuration file for ${DOMAIN}"
        fi
        ;;
    *)
        echo "Usage: create|delete|enable|disable domain-name.tld"
        ;;
esac
