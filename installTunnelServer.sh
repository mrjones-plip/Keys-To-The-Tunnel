#!/bin/bash

DOMAIN="$1"
EMAIL="$2"

clear

if [ -z "$DOMAIN" ]
then
  echo "ERROR - Domain is empty. Call should be:"
  echo
  echo "    ./installTunnelServer.sh DOMAIN EMAIL"
  echo
  echo "Exiting"
  echo
  exit
fi

if [ -z "$EMAIL" ]
then
  echo "ERROR - Email is empty. Call should be:"
  echo
  echo "    ./installTunnelServer.sh DOMAIN EMAIL"
  echo
  echo "Exiting"
  echo
  exit
fi

USERS_FILE='user.txt'
if [ ! -f "$USERS_FILE" ]; then
  echo "ERROR - $USERS_FILE file with list of GH usernames does not exist."
  echo
  echo "Exiting"
  echo
  exit
fi

# thanks https://stackoverflow.com/a/18216122
if [ "$EUID" -ne 0 ]; then
  echo "ERROR - You are not root"
  echo
  echo "Exiting"
  echo
#  exit
fi

echo
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
echo
echo "Creating accounts for these GitHub users:"
echo
for i in "${VALID_USERS[@]}"; do
  echo " - $i"
done
echo
echo "See https://github.com/mrjones-plip/Keys-To-The-Tunnel for more info"
echo
echo "Press any key to continue or \"ctrl + c\" to exit"
echo
read -n1 -s

# install caddy, rpl & certbot then enable mods
echo
echo " ------ Updating OS and installing required software, this might take a while... ------ "
echo
apt-get -qq update&&apt-get -y -qqq dist-upgrade
if ! command -v "caddy" &>/dev/null; then
  sudo apt -qqq install -y debian-keyring debian-archive-keyring apt-transport-https libnss3-tools \
    snapd python3 python3-pip rpl
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

echo "
#!/bin/bash
echo '${DOMAIN}'
" > /var/www/html/say_my_name.sh
  chmod +x /var/www/html/say_my_name.sh
fi
# always restart in case it was updated above
systemctl restart caddy
echo "  ~~ DONE! "

echo
echo " ------ Adding users... ------ "
echo
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

echo
echo " ------ Setting MOTD... ------ "
echo
sudo chmod -x /etc/update-motd.d/*
cp motd /etc/update-motd.d/02-ssh-tunnel-info
sudo chmod +x /etc/update-motd.d/02-ssh-tunnel-info
echo "  ~~ DONE! "

echo
echo " ------ Adding SSH keys for users and setting file perms. This may take a while... ------ "
echo
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

echo
echo " ------ Adding caddy vhost files for all! user...  ------ "
echo
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
        to https://127.0.0.1:${rand}
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

echo
echo " ------  Adding caddy vhost for primary ${DOMAIN}...  ------ "
echo

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

echo
echo " ------ Reloading Caddy and fetching Let's Encrypt certs... ------ "
echo
systemctl restart caddy
echo "  ~~ DONE! "

echo
echo " ------  Compiling final HTML for base website...  ------ "
echo
cp ./index.html ./kttt-logo.svg ./jquery-3.6.2.min.js /var/www/html/

All_USERS_PORT=$(grep -h USERINFO /etc/caddy/sites-enabled/*|cut -d' ' -f7,8)
PORT_HANDLE_HTML=''
for user_port in "${All_USERS_PORT[@]}"; do
  handle=$(echo $user_port | cut -f1 -d' ')
  port=$(echo $user_port | cut -f2 -d' ')
  PORT_HANDLE_HTML="${PORT_HANDLE_HTML}<option port=\"${port}\">${handle}</option>\n"
done
rpl -q --encoding UTF-8 -q PUT_PORT_HANDLE_HERE "$PORT_HANDLE_HTML" /var/www/html/index.html
rpl -q --encoding UTF-8 -q PUT_DOMAIN_HERE "$DOMAIN" /var/www/html/index.html

if [ -f "./logo.svg" ]; then
  cp ./logo.svg /var/www/html/
  rpl -q --encoding UTF-8 -q BRANDED_LOGO_HERE "<img alt="logo provided by kttt host" id=\"logo\" src=\"./logo.svg\" />" /var/www/html/index.html
else
  rpl -q --encoding UTF-8 -q BRANDED_LOGO_HERE "" /var/www/html/index.html
fi

echo
echo "Output saved to /var/www/html/index.html can be seen at https://${DOMAIN}"
echo

echo " ------ All done - enjoy! ------ "
echo
