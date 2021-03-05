#!/bin/bash

# todo - put in a single loop?  fewer loops?
# todo - check for Nth run to not create users that already exist etc
# todo - save decent looking HTML instructions in $DOMAIN vhost
# todo - maybe check for ubuntu?
# todo - consolidate certbot calls with "-d DOMAIN" to reduce API calls?
# todo - check for GH user exists (http 200) and user having keys before creating account

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
  echo "ERROR - You are not as root"
  echo ""
  echo "Exiting"
  echo ""
  exit
fi

echo ""
echo "This script assumes you're root and assumes you"
echo "want to set a bunch of SSH tunnels to reverse proxy"
echo "HTTPs and HTTP traffic."
echo ""
echo "See https://github.com/mrjones-plip/mrjones-medic-scratch/tree/main/SshTunnelServer "
echo "for more info"
echo ""
echo "Press any key to continue or \"ctrl + c\" to exit"
echo ""
read -n1 -s

# install apache, rpl & certbot then enable mods
# todo - uncomment this - this way to speed testing
echo ""
echo "Installing required software..."
echo ""
apt -q update&&apt -y -q dist-upgrade&&apt -q install -y  apache2  rpl&&systemctl --now enable apache2
sudo snap install core; sudo snap refresh core
sudo snap install --classic certbot
a2enmod proxy proxy_ajp proxy_http rewrite deflate headers proxy_balancer proxy_connect proxy_html

# todo validate this works
echo ""
echo "Adding users..."
echo ""
cp ./press_to_exit.sh /bin/press_to_exit.sh
for i in $(cat user.txt); do
  useradd -m -d /home/$i -s /bin/press_to_exit.sh $i
done

echo ""
echo "Setting MOTD..."
echo ""
sudo chmod -x /etc/update-motd.d/*
cp motd /etc/update-motd.d/02-ssh-tunnel-info
sudo chmod +x /etc/update-motd.d/02-ssh-tunnel-info

# create .ssh dir and authorized_keys with right perms and ownership
# todo validate this works
for i in $(cat user.txt); do
  mkdir /home/$i/.ssh
  touch /home/$i/.ssh/authorized_keys
  chown $i:$i /home/$i/.ssh
  chown $i:$i /home/$i/.ssh/authorized_keys
  chmod 700 /home/$i/.ssh
  chmod 600 /home/$i/.ssh/authorized_keys
done

# fetch .ssh keys into authorized keys file
for i in $(cat user.txt); do
  curl -s https://github.com/$i.keys -o /home/$i/.ssh/authorized_keys
done

# add mrjones key to all to help testing (optional)
for i in $(cat user.txt); do
  curl -s https://github.com/mrjones-plip.keys >>/home/$i/.ssh/authorized_keys
done

#  create one file per user vhost and a custom port per file.
for i in `cat user.txt`; do
  cp ./apache.conf /etc/apache2/sites-available/$i.$DOMAIN.conf
  rpl --encoding UTF-8  -q SUBDOMAIN $i /etc/apache2/sites-available/$i.$DOMAIN.conf
  rpl --encoding UTF-8  -q DOMAIN $DOMAIN /etc/apache2/sites-available/$i.$DOMAIN.conf
  rand=`shuf -i1000-5000 -n1`
  rpl --encoding UTF-8  -q PORT $rand /etc/apache2/sites-available/$i.$DOMAIN.conf
done


# enable vhosts
for i in `cat user.txt`; do
  a2ensite $i.$DOMAIN.conf
done

#enable certbot certs , change email
for i in `cat user.txt`; do
  sudo certbot  --apache   --non-interactive   --agree-tos   --email $EMAIL --domains $i.$DOMAIN
done

# reload apache so new config takes effect
systemctl reload apache2

echo ""
echo "Outputting mapping..."
echo ""
echo "-----------------"
grep '        ProxyPassReverse ' /etc/apache2/sites-available/*|cut -d/ -f5,8|cut -d: -f1,3
echo "-----------------"
echo ""


echo ""
echo "Done!"
echo ""
