#!/bin/bash
### Set Language
TEXTDOMAIN=virtualhost

### Set default parameters
action=$1
domain=$2
rootDir=$3
IFS='/' read -r -a rootDirs <<< "$rootDir"
owner=$(who am i | awk '{print $1}')
sitesEnable='/etc/nginx/sites-enabled/'
sitesAvailable='/etc/nginx/sites-available/'
userDir='/var/www/'
conf='.conf'

if [ "$(whoami)" != 'root' ]; then
	echo $"You do not have permission to run $0 as non-root user. Use sudo"
		exit 1;
fi

if [ "$action" != 'create' ] && [ "$action" != 'delete' ]; then
	echo $"You must include an action ('create' or 'delete')"
	exit 1;
fi

while [ "$domain" == "" ]; do
	echo -e $"Please provide a domain. e.g. dev, staging"
	read domain
done

if [ "$rootDir" == "" ]; then
	rootDir=${domain//./}
fi

### if root dir starts with '/', don't use /var/www as default starting point
if [[ "$rootDir" =~ ^/ ]]; then
	userDir=''
fi

### rootDir=$userDir$rootDir

if [ "$action" == 'create' ]; then
	### check if domain already exists
	if [ -e $sitesAvailable$domain ]; then
		echo -e $"The domain already exists.\nPlease try again."
		exit;
	fi

	### check if directory exists or not
	if ! [ -d $userDir$rootDir ]; then
		### create the directory(s)
		newDir=$userDir
		for dir in "${rootDirs[@]}"
		do
			newDir="$newDir/$dir"
			if ! [ -d $newDir ]; then
				mkdir $newDir
			fi
			### give permission to root dir
			chmod 755 $newDir
		done
		### write test PHP file in the new domain dir
		if ! echo "<?php echo phpinfo(); ?>" > $userDir$rootDir/phpinfo.php
			then
				echo $"ERROR: Not able to write file $userDir$rootDir/phpinfo.php. Please check permissions."
				exit;
		else
				echo $"Added content to $userDir$rootDir/phpinfo.php"
		fi
		### write index file
		if ! echo "<!DOCTYPE html>
			<html>
			<body>
			Hello world!
			</body>
			</html>" > $userDir$rootDir/index.html
			then
				echo $"ERROR: Not able to write file $userDir/$rootDir/index.html. Please check permissions."
				exit;
		else
				echo $"Added content to $userDir$rootDir/index.html"
		fi
	fi

	### create virtual host rules file
	if ! echo "server {
		listen   80;
		root $userDir$rootDir;
		index index.php index.html index.htm;
		server_name $domain;

		# serve static files directly
		location ~* \.(jpg|jpeg|gif|css|png|js|ico|html)$ {
			access_log off;
			expires max;
		}

		# removes trailing slashes (prevents SEO duplicate content issues)
		if (!-d \$request_filename) {
			rewrite ^/(.+)/\$ /\$1 permanent;
		}

		# unless the request is for a valid file (image, js, css, etc.), send to bootstrap
		if (!-e \$request_filename) {
			rewrite ^/(.*)\$ /index.php?/\$1 last;
			break;
		}

		# removes trailing 'index' from all controllers
		if (\$request_uri ~* index/?\$) {
			rewrite ^/(.*)/index/?\$ /\$1 permanent;
		}

		# catch all
		error_page 404 /index.php;

		location ~ \.php$ {
			fastcgi_split_path_info ^(.+\.php)(/.+)\$;
			fastcgi_pass 127.0.0.1:9000;
			fastcgi_index index.php;
			include fastcgi_params;
		}

		location ~ /\.ht {
			deny all;
		}

	}" > $sitesAvailable$domain$conf
	then
		echo -e $"There was an error creating $domain$conf file"
		exit;
	else
		echo -e $"\nNew virtual host $domain created\n"
	fi

	### Add domain in /etc/hosts
	if ! echo "127.0.0.1	$domain" >> /etc/hosts
		then
			echo $"ERROR: Not able write to /etc/hosts"
			exit;
	else
			echo -e $"Host added to /etc/hosts file \n"
	fi

    ### Add domain in /mnt/c/Windows/System32/drivers/etc/hosts (Windows Subsytem for Linux)
	if [ -e /mnt/c/Windows/System32/drivers/etc/hosts ]; then
		if ! echo -e "\r127.0.0.1       $domain" >> /mnt/c/Windows/System32/drivers/etc/hosts
		then
			echo $"ERROR: Not able to write in /mnt/c/Windows/System32/drivers/etc/hosts (Hint: Try running Bash as administrator)"
		else
			echo -e $"Host added to /mnt/c/Windows/System32/drivers/etc/hosts file \n"
		fi
	fi

	if [ "$owner" == "" ]; then
		chown -R $(whoami):www-data $userDir$rootDir
	else
		chown -R $owner:www-data $userDir$rootDir
	fi

	### enable website
	ln -s $sitesAvailable$domain$conf $sitesEnable$domain$conf

	### restart Nginx
	service nginx restart

	### show the finished message
	echo -e $"Complete! \nYou now have a new Virtual Host \nYour new host is: http://$domain \nAnd its located at $userDir$rootDir"
	exit;
else
	### check whether domain already exists
	if ! [ -e $sitesAvailable$domain$conf ]; then
		echo -e $"This domain does not exists.\nPlease try again."
		exit;
	else
		### Delete domain in /etc/hosts
		newhost=${domain//./\\.}
		sed -i "/$newhost/d" /etc/hosts

		### Delete domain in /mnt/c/Windows/System32/drivers/etc/hosts (Windows Subsytem for Linux)
		if [ -e /mnt/c/Windows/System32/drivers/etc/hosts ]
		then
			newhost=${domain//./\\.}
			sed -i "/$newhost/d" /mnt/c/Windows/System32/drivers/etc/hosts
		fi

		### disable website
		rm $sitesEnable$domain$conf

		### restart Nginx
		service nginx restart

		### Delete virtual host rules files
		rm $sitesAvailable$domain$conf
	fi

	### check if directory exists or not
	if [ -d $userDir$rootDir ]; then
		echo -e $"Delete host root directory ? (y/N)"
		read deldir

		if [ "$deldir" == 'y' -o "$deldir" == 'Y' ]; then
			### Delete the directory
			rm -rf $userDir$rootDir
			echo -e $"Directory deleted"
		else
			echo -e $"Host directory conserved"
		fi
	else
		echo -e $"Host directory not found. Ignored"
	fi

	### show the finished message
	echo -e $"Complete!\nYou just removed Virtual Host $domain"
	exit 0;
fi
