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

  if [ -f /home/"$i"/.ssh/authorized_keys ]; then
    keys=$(curl -s /dev/stdout https://github.com/${USER}.keys)
    if [[ ! -z "$keys" ]] && [[ $keys != "Not Found" ]]; then
      VALID_USERS+=("$USER")
    else
      echo " - Skipping $USER, no SSH key found"
    fi
  else
    VALID_USERS+=("$USER")
    echo " - Skipping $USER, account and keys already exist locally"
  fi
done
echo "  ~~ DONE! "

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

# install caddy, rpl & certbot then enable mods
echo ""
echo " ------ Updating OS and installing required software, this might take a while... ------ "
echo ""
apt-get -qq update&&apt-get -y -qqq dist-upgrade
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
  chmod -R 750 /etc/letsencrypt/
  chgrp -R caddy /etc/letsencrypt/

  echo " ------ Running 1 time set up for certbot - be prepared to set a DNS entry  ------ "
  certbot certonly --manual --manual-auth-hook /etc/letsencrypt/acme-dns-auth.py \
     --preferred-challenges dns --debug-challenges                               \
     -d "${DOMAIN}" -d \*."${DOMAIN}"
fi
# always restart in case it was updated above
systemctl restart caddy
echo "  ~~ DONE! "

echo ""
echo " ------ Adding users... ------ "
echo ""
cp ./press_to_exit.sh /bin/press_to_exit.sh
sleep 1
for i in "${VALID_USERS[@]}"; do
  if id "$i" &>/dev/null; then
      echo "${i} user already exists"
  else
      useradd -m -d /home/$i -s /bin/press_to_exit.sh $i
  fi
done
echo "  ~~ DONE! "

echo ""
echo " ------ Setting MOTD... ------ "
echo ""
sudo chmod -x /etc/update-motd.d/*
cp motd /etc/update-motd.d/02-ssh-tunnel-info
sudo chmod +x /etc/update-motd.d/02-ssh-tunnel-info
echo "  ~~ DONE! "

echo ""
echo " ------ Adding SSH keys for users and setting file perms. This may take a while... ------ "
echo ""
for i in "${VALID_USERS[@]}"; do
  if [ ! -f /home/"$i"/.ssh/authorized_keys ]; then
    mkdir -p /home/"$i"/.ssh
    touch /home/"$i"/.ssh/authorized_keys
    chown $i:$i /home/"$i"/.ssh
    chown $i:$i /home/"$i"/.ssh/authorized_keys
    chmod 700 /home/"$i"/.ssh
    chmod 600 /home/"$i"/.ssh/authorized_keys
    curl -s https://github.com/"$i".keys -o /home/"$i"/.ssh/authorized_keys
  fi
done
echo "  ~~ DONE! "

echo ""
echo " ------ Adding caddy vhost files for all! user...  ------ "
echo ""
for i in "${VALID_USERS[@]}"; do
  FQDNconf="${i}-${DOMAIN}.conf"
  if [ ! -f /etc/caddy/sites-enabled/"$FQDNconf" ]; then
    echo "writing $FQDNconf"
    rand=`shuf -i1000-5000 -n1`

    echo "
    # USERINFO ${i} ${rand}
    http://${i}.${DOMAIN} {
      redir https://{host}{uri}
    }
    ${i}.${DOMAIN} {
      tls /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/letsencrypt/live/${DOMAIN}/privkey.pem
      reverse_proxy 127.0.0.1:${rand}
    }
    http://${i}-ssl.${DOMAIN} {
        redir https://{host}{uri}
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
    }
    " > /etc/caddy/sites-enabled/"$FQDNconf"
  else
    echo "skipping $FQDNconf"
  fi
done
echo "  ~~ DONE! "

echo ""
echo " ------  Adding caddy vhost for primary ${DOMAIN}...  ------ "
echo ""

echo "
http://${DOMAIN} {
  redir https://{host}{uri}
}
${DOMAIN} {
  tls /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/letsencrypt/live/${DOMAIN}/privkey.pem
  root * /var/www/html
  file_server
}
" > /etc/caddy/sites-enabled/0000-"${DOMAIN}".conf
echo "  ~~ DONE! "

echo ""
echo " ------ Reloading Caddy and fetching Let's Encrypt certs... ------ "
echo ""
systemctl restart caddy
echo "  ~~ DONE! "

# grep ports and users out of config files
MAPPING_NOSSL=$(grep -h USERINFO /etc/caddy/sites-enabled/*|cut -d' ' -f7,8 | awk '{print "\t" $0}')
MAPPING_SSL=$(grep -h USERINFO /etc/caddy/sites-enabled/*|cut -d' ' -f7,8 | awk '{print "\t" $0}')

SAMPLE_HOST=$(grep -h medic-tunnel.plip.com /etc/caddy/sites-enabled/*|grep http|tail -n1 |cut -f3 -d'/'|cut -f1 -d'{')
SAMPLE_PORT=$(grep -h USERINFO /etc/caddy/sites-enabled/*|cut -d' ' -f7,8|tail -n1|cut -f2 -d' ')
SAMPLE_LOGIN=$(grep -h USERINFO /etc/caddy/sites-enabled/*|cut -d' ' -f7,8|tail -n1|cut -f1 -d' ')

# shellcheck disable=SC2140
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

    Caddy is configured on the http hosts to speak http to your localhost
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
echo "All this was saved to /var/www/html/index.html can be seen at https://${DOMAIN}"
echo ""

echo " ------ All done - enjoy! ------ "
echo ""
