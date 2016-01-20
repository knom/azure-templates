#!/bin/bash
dbName="$1"
dbUser="$2"
dbPassword="$3"
dbHost="$4"

# Following a tutorial on https://www.digitalocean.com/community/tutorials/how-to-install-wordpress-on-ubuntu-14-04
wget http://wordpress.org/latest.tar.gz -P /tmp/
tar xzvf /tmp/latest.tar.gz -C /tmp/

# Following a tutorial on https://www.digitalocean.com/community/tutorials/how-to-install-linux-nginx-mysql-php-lemp-stack-on-ubuntu-14-04
sudo apt-get update -qq -y
sudo apt-get install nginx -qq -y
sudo apt-get install php5-fpm php5-mysql -qq -y

# sudo nano /etc/php5/fpm/php.ini
#	;cgi.fix_pathinfo=0 //remove ; --> 0
    
cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php

sed -i "s/database_name_here/$dbName/" /tmp/wordpress/wp-config.php
sed -i "s/localhost/$dbHost/" /tmp/wordpress/wp-config.php
sed -i "s/password_here/$dbPassword/" /tmp/wordpress/wp-config.php
sed -i "s/username_here/$dbUser/" /tmp/wordpress/wp-config.php

sudo mkdir -p /var/www/html
sudo rsync -avP /tmp/wordpress/ /var/www/html/
# sudo chown -R demo:www-data *

mkdir /var/www/html/wp-content/uploads
# sudo chown -R demo:www-data /var/www/html/wp-content/uploads

cat > /tmp/wordpress.log << eof
server {
   listen 80 default_server;
   listen [::]:80 default_server ipv6only=on;
   
   root /var/www/html;
   index index.php index.html index.htm;
   
   server_name localhost;
   
   location / {
      try_files \$uri \$uri/ /index.php?q=\$uri&\$args;
   }
   
   location ~ \.php\$ {
      try_files \$uri =404;
      fastcgi_split_path_info ^(.+\.php)(/.+)\$;
      fastcgi_pass unix:/var/run/php5-fpm.sock;
      fastcgi_index index.php;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      include fastcgi_params;
   }
   
   error_page 404 /404.html;
   
   error_page 500 502 503 504 /50x.html;
   location = /50x.html {
      root /usr/share/nginx/html;
   }
}
eof

sudo mv /tmp/wordpress.log /etc/nginx/sites-available/wordpress

sudo ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default

sudo service nginx stop
sudo service nginx start
sudo service php5-fpm stop
sudo service php5-fpm start