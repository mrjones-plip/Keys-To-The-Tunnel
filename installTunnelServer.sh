#!/bin/bash

# todo - check for Nth run to not create users that already exist etc
# todo - maybe check for ubuntu?
# todo - consolidate certbot calls with "-d DOMAIN" via SAN to reduce API calls?
# todo - cache SSH keys on first validation to avoid subsequent API calls to GH to get keys again

DOMAIN="$1"
EMAIL="$2"

clear

if [ -z "$DOMAIN" ]
then
  echo "ERROR - Domain is empty. Call should be:"
  echo ""
  echo "    ./installTunnelServer.sh DOMAIN EMAIL"
  echo ""
  echo "Exiting"
  echo ""
  exit
fi

if [ -z "$EMAIL" ]
then
  echo "ERROR - Email is empty. Call should be:"
  echo ""
  echo "    ./installTunnelServer.sh DOMAIN EMAIL"
  echo ""
  echo "Exiting"
  echo ""
  exit
fi

USERS_FILE='user.txt'
if [ ! -f "$USERS_FILE" ]; then
  echo "ERROR - $USERS_FILE file with list of GH usernames does not exist."
  echo ""
  echo "Exiting"
  echo ""
  exit
fi

# thanks https://stackoverflow.com/a/18216122
if [ "$EUID" -ne 0 ]; then
  echo "ERROR - You are not root"
  echo ""
  echo "Exiting"
  echo ""
#  exit
fi

echo ""
echo " ------ Verifying users who have SSH keys on GH, this may take a while... ------ "
echo " "
VALID_USERS=()
for USER in $(cat user.txt); do
  keys=$(curl -s /dev/stdout https://github.com/${USER}.keys)
  if [[ ! -z "$keys" ]]; then
    VALID_USERS+=("$USER")
  else
    echo " - Skipping $USER, no SSH key found"
  fi
done

echo " "
echo "This script assumes:"
echo " "
echo " - you're root on Ubuntu"
echo " - you have a wildcard DNS entry pointed to this server "
echo "   for *.$DOMAIN"
echo " - you want to set up a bunch of SSH tunnels to reverse  "
echo "   proxy HTTPs and HTTP traffic"
echo " - are on on a machine dedicated to this purpose"
echo ""
echo "Will create accounts for these GitHub users using their"
echo "SSH keys on GitHub:"
echo ""
for i in "${VALID_USERS[@]}"; do
  echo " - $i"
done
echo ""
echo "See https://github.com/mrjones-plip/mrjones-medic-scratch/tree/main/SshTunnelServer "
echo "for more info"
echo ""
echo "Press any key to continue or \"ctrl + c\" to exit"
echo ""
read -n1 -s

# install apache, rpl & certbot then enable mods
echo ""
echo " ------ Updating OS and installing required software, this might take a while... ------ "
echo ""
apt -qq update&&apt -y -qqq dist-upgrade&&apt -qqq install -y  apache2  rpl&&systemctl --now enable apache2
sudo snap install core; sudo snap refresh core
sudo snap install --classic certbot
mv /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-available/000-default-ssl.conf
a2ensite 000-default-ssl.conf

echo ""
echo " ------ Adding users... ------ "
echo ""
cp ./press_to_exit.sh /bin/press_to_exit.sh
sleep 1
for i in "${VALID_USERS[@]}"; do
  useradd -m -d /home/$i -s /bin/press_to_exit.sh $i
done

echo ""
echo " ------ Setting MOTD... ------ "
echo ""
sudo chmod -x /etc/update-motd.d/*
cp motd /etc/update-motd.d/02-ssh-tunnel-info
sudo chmod +x /etc/update-motd.d/02-ssh-tunnel-info

echo ""
echo " ------ Adding SSH keys for users and setting file perms. This may take a while... ------ "
echo ""
for i in "${VALID_USERS[@]}"; do
  mkdir -p /home/$i/.ssh
  touch /home/$i/.ssh/authorized_keys
  chown $i:$i /home/$i/.ssh
  chown $i:$i /home/$i/.ssh/authorized_keys
  chmod 700 /home/$i/.ssh
  chmod 600 /home/$i/.ssh/authorized_keys
  curl -s https://github.com/$i.keys -o /home/$i/.ssh/authorized_keys
done

echo ""
echo "Adding apache vhost files..."
echo ""
for i in "${VALID_USERS[@]}"; do
  rand=`shuf -i1000-5000 -n1`
  FQDNconf="${i}.${DOMAIN}.conf"
  FQDN_ssl_conf="${i}-ssl.${DOMAIN}.conf"

  cp ./apache.conf /etc/apache2/sites-available/$FQDNconf
  cp ./apache.ssl.conf /etc/apache2/sites-available/$FQDN_ssl_conf

  rpl -q --encoding UTF-8  -q SUBDOMAIN $i /etc/apache2/sites-available/$FQDNconf
  rpl -q  --encoding UTF-8  -q SUBDOMAIN $i /etc/apache2/sites-available/$FQDN_ssl_conf

  rpl  -q --encoding UTF-8  -q DOMAIN $DOMAIN /etc/apache2/sites-available/$FQDNconf
  rpl  -q --encoding UTF-8  -q DOMAIN $DOMAIN /etc/apache2/sites-available/$FQDN_ssl_conf

  rpl  -q --encoding UTF-8  -q PORT $rand /etc/apache2/sites-available/$FQDNconf
  rpl  -q --encoding UTF-8  -q PORT $rand /etc/apache2/sites-available/$FQDN_ssl_conf

  a2ensite $FQDNconf $FQDN_ssl_conf
done

echo ""
echo " ------ Fetching certs from Let's Encrypt... ------ "
echo ""
for i in "${VALID_USERS[@]}"; do
  sudo certbot  --apache   --non-interactive   --agree-tos   --email $EMAIL --domains $i.$DOMAIN
done

echo ""
echo " ------ Creating last cert for bare $DOMAIN domain... ------ "
echo ""
sudo certbot  --apache   --non-interactive   --agree-tos   --email $EMAIL --domains $DOMAIN

echo ""
echo " ------ Configuring and Reloading apache... ------ "
echo ""
a2enmod proxy proxy_ajp proxy_http rewrite deflate headers proxy_balancer proxy_connect proxy_html ssl
systemctl reload apache2
MAPPING_NOSSL=$(grep -ri -m1 'ProxyPassReverse' /etc/apache2/sites-available/*|grep -v '\-ssl\.'|cut -d/ -f5,8|cut -d: -f1,3|awk 'BEGIN{FS=OFS=":"}{print $2 FS  $1}'|sed -r 's/.conf//g'|sed -r 's/:/\t/g'| awk '{print "\t" $0}')
MAPPING_SSL=$(grep -ri -m1 'ProxyPassReverse' /etc/apache2/sites-available/*-ssl\.*|cut -d/ -f5,8|cut -d: -f1,3|awk 'BEGIN{FS=OFS=":"}{print $2 FS  $1}'|sed -r 's/.conf//g'|sed -r 's/:/\t/g'| awk '{print "\t" $0}')
SAMPLE_PORT=$(grep -ri -m1 'ProxyPassReverse' /etc/apache2/sites-available/*|cut -d/ -f5,8|cut -d: -f3|tail -n1)
SAMPLE_HOST=$(grep -ri -m1 'ProxyPassReverse' /etc/apache2/sites-available/*|cut -d/ -f5,8|cut -d: -f1|sed 's/.conf//g'|tail -n1)
SAMPLE_LOGIN=$(grep -ri -m1 'ProxyPassReverse' /etc/apache2/sites-available/*|cut -d/ -f5,8|cut -d: -f1|sed 's/.conf//g'|tail -n1|cut -d. -f1)

echo "
<style>
* {
	color: white;
	background: black;
}
</style>
<pre>
ports for local <code>http</code> hosts:

$MAPPING_NOSSL

ports for local <code>https</code> hosts:

$MAPPING_SSL

use:

    ssh -T -R PORT-FROM-ABOVE:127.0.0.1:PORT-ON-DEV GH-HANDLE@${DOMAIN}

example:

    expose local port 80 on https://${SAMPLE_HOST} using ${SAMPLE_LOGIN}'s GH keys

    ssh -T -R ${SAMPLE_PORT}:127.0.0.1:80 ${SAMPLE_LOGIN}@${DOMAIN}

note:

    Apache is configured on the http hosts to speak http to your localhost
    server. Conversely, it is configured to speak https on the https hosts.
    If you mix these up it will try and speak https to http (or vise versa)
    and it will fail.

more:

    https://github.com/mrjones-plip/mrjones-medic-scratch/tree/main/SshTunnelServer
</pre>
" > /var/www/html/index.html

echo ""
echo " ------ Here's the final mapping for http: ------ "
echo ""
echo "${MAPPING_NOSSL}"
echo ""
echo " ------ Here's the final mapping for https: ------ "
echo ""
echo "${MAPPING_SSL}"

echo ""
echo "All this was saved to /var/www/html/index.html which is found on https://${DOMAIN}"
echo ""

echo " ------ All done - enjoy! ------ "
echo ""