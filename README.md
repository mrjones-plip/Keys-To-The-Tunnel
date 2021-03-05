# Keys-To-The-Tunnel

 
## Intro

Keys-To-The-Tunnel is for when you have a lot of GitHub Developers who have added their SSH key to GitHub (e.g. [here's mine](https://github.com/mrjones-plip.keys)) and they also are doing local development of apps that they either need to share with others via the internet or they need valid TLS certificates to test with, or both!

The script will:
1. Create an SSH login on the host
1. Lock this login to only allow SSH tunnels
1. Create an Apache vhost for this login, with the `GH-USERNAME.domain.com`
1. Create an SSL certificate with Let's Encrypt for `GH-USERNAME.domain.com`
1. Put instructions to use the SSH tunnels at `domain.com`

This script is [hosted on GitHub](https://github.com/mrjones-plip/mrjones-medic-scratch/tree/main/SshTunnelServer).

Keys-To-The-Tunnel is named after the fact that it uses SSH tunnels and the keys for this are pivital to why it exists: easily provision accounts from GH users based off their SSH keys.

## Requirements

Right now this very narrowly scoped, so requirements are:
1. An Ubuntu 20.04 server
1. A public IP for the server
1. An A record pointing to the public IP (AAAA if ya wanna be IPv6 classy)
1. a wildcard CNAME entry pointing to the A record
1. SSH server [locked to keys only](https://www.linuxbabe.com/linux-server/setup-passwordless-ssh-login) (optional, but is very good idea)

Development was done locally and then in Digital Ocean.

## Running

1. SSH as root to your Ubuntu server with public IP
1. clone this repo with `git clone https://github.com/mrjones-plip/mrjones-medic-scratch`
1. cd into repo and add create `user.txt` with your github users, one per line
1. run the install script with `./installTunnelServer.sh DOMAIN.COM EMAIL` replacing `DOMAIN.COM` with your real domain from step 3 in Requirements and replacing `EMAIL` with your email which will be used to agree to Let's Encrypt TOS and to get notifications about expiring certs.
1. Send users the URL `DOMAIN.COM` which now lists how to use the server
