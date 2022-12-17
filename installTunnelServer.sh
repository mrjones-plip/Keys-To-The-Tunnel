#!/bin/bash

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
# todo - uncomment for release
#  keys=$(curl -s /dev/stdout https://github.com/${USER}.keys)
#  if [[ ! -z "$keys" ]] && [[ $keys != "Not Found" ]]; then
    VALID_USERS+=("$USER")
#  else
#    echo " - Skipping $USER, no SSH key found"
#  fi
done

echo " "
echo "This script assumes:"
echo " "
echo " - root on Ubuntu 20.04"
echo " - DNS to this server for $DOMAIN"
echo " - wildcard DNS entry to this server for *.$DOMAIN"
echo " - are on on a machine dedicated to this purpose"
echo " - you're in a good mood, ready for some SSH Tunnel awesomeness!"
echo ""
echo "Creating accounts for these GitHub users:"
echo ""
for i in "${VALID_USERS[@]}"; do
  echo " - $i"
done
echo ""
echo "See https://github.com/mrjones-plip/Keys-To-The-Tunnel for more info"
echo ""
echo "Press any key to continue or \"ctrl + c\" to exit"
echo ""
read -n1 -s

# install apache, rpl & certbot then enable mods
echo ""
echo " ------ Updating OS and installing required software, this might take a while... ------ "
echo ""
apt -qq update&&apt -y -qqq dist-upgrade
if ! command -v "caddy" &>/dev/null; then
  sudo apt -qqq install -y debian-keyring debian-archive-keyring apt-transport-https libnss3-tools  snapd python3 python3-pip
  ln -s /usr/bin/python3 /usr/bin/python
  python3 -m pip install requests
  sudo snap install core
  sudo snap refresh core
  sudo snap install --classic certbot
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
  sudo apt -qqq update
  sudo apt -qqq install caddy
  systemctl start caddy
  systemctl enable caddy
  echo "import sites-enabled/*" >> /etc/caddy/Caddyfile
  mkdir /etc/caddy/sites-enabled
  mkdir -p /var/www/html
  mkdir -p /etc/letsencrypt/live/${DOMAIN}
  curl -so /etc/letsencrypt/acme-dns-auth.py https://raw.githubusercontent.com/joohoi/acme-dns-certbot-joohoi/master/acme-dns-auth.py
  chmod 0700 /etc/letsencrypt/acme-dns-auth.py

  echo " ------ Running 1 time set up for certbot - be prepared to set a DNS entry  ------ "
  certbot certonly --manual --manual-auth-hook /etc/letsencrypt/acme-dns-auth.py \
     --preferred-challenges dns --debug-challenges                               \
     -d "${DOMAIN}" -d \*."${DOMAIN}"
fi
# always restart in case it was updated above
systemctl restart caddy
echo "   DONE! "

echo ""
echo " ------ Adding users... ------ "
echo ""
cp ./press_to_exit.sh /bin/press_to_exit.sh
sleep 1
for i in "${VALID_USERS[@]}"; do
  if id "$1" &>/dev/null; then
      echo "${i} user already exists"
  else
      useradd -m -d /home/$i -s /bin/press_to_exit.sh $i
  fi
done
echo "   DONE! "

echo ""
echo " ------ Setting MOTD... ------ "
echo ""
sudo chmod -x /etc/update-motd.d/*
cp motd /etc/update-motd.d/02-ssh-tunnel-info
sudo chmod +x /etc/update-motd.d/02-ssh-tunnel-info
echo "   DONE! "

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
  # todo uncomment
#  curl -s https://github.com/$i.keys -o /home/$i/.ssh/authorized_keys
done
echo "   DONE! "

echo ""
echo " ------ Adding caddy vhost files for each user...  ------ "
echo ""
for i in "${VALID_USERS[@]}"; do
  rand=`shuf -i1000-5000 -n1`
  FQDNconf="${i}-${DOMAIN}.conf"

  echo "
  ${i}.${DOMAIN} {
    tls /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/letsencrypt/live/${DOMAIN}/privkey.pem
    reverse_proxy 127.0.0.1:${rand}
  }
  ${i}-ssl.${DOMAIN} {
    tls  /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/letsencrypt/live/${DOMAIN}/privkey.pem
    reverse_proxy {
      to https://192.168.68.1:444
      transport http {
        tls
        tls_insecure_skip_verify
    }
  }
  " > /etc/caddy/sites-enabled/$FQDNconf
done
echo "   DONE! "

echo ""
echo " ------  Adding caddy vhost for primary ${DOMAIN}...  ------ "
echo ""

echo "
${DOMAIN} {
  tls /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/letsencrypt/live/${DOMAIN}/privkey.pem
  root * /var/www/html
  file_server
}
" > /etc/caddy/sites-enabled/0000-${DOMAIN}.conf
echo "   DONE! "


exit

echo ""
echo " ------ Reloading Caddy and fetching Let's Encrypt certs... ------ "
echo ""
systemctl restart caddy
echo "   DONE! "

echo "
<style>
* {
	color: white;
	background: black;
}
pre {
  width: 600px;
  text-align: left;
}
</style>
<center>
<h1>Keys-To-The-Tunnel</h1>
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
</pre>
<p><a href="https://github.com/mrjones-plip/Keys-To-The-Tunnel">Keys-To-The-Tunnel @ GitHub</a>
</center>
" > /var/www/html/index.html

if [ -f "./logo.svg" ]; then
  cp ./logo.svg /var/www/html/
  echo "<center><p><img src='./logo.svg'></p></center>" >> /var/www/html/index.html
fi


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
