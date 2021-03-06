#  Keys-To-The-Tunnel
 
## Intro

Keys-To-The-Tunnel is for when you have a lot of GitHub Developers who have added their SSH key to GitHub (e.g. [here's mine](https://github.com/mrjones-plip.keys)) and they also are doing local development of apps that they either need to share with others via the internet or they need valid TLS certificates to test with, or both!

Given a list of GH users and a `DOMAIN`, the script will give each user:
1. A login 
1. GH SSH key(s) put in `~/.ssh/authorized_keys`  
1. Only allow SSH tunnels, no shells
1. 2 vhosts for `http` and `https` localhost. GH name is a subdomain
1. Valid SSL certificates from Let's Encrypt
1. Instructions saved in `DOMAIN`

This script is [hosted on GitHub](https://github.com/mrjones-plip/mrjones-medic-scratch/tree/main/SshTunnelServer).

## FAQ

[FAQ!](faq.md) ;)

## Requirements

Right now this very narrowly scoped, so requirements are:
1. An Ubuntu 20.04 server
1. A public IP for the server
1. An A record pointing to the public IP (AAAA if ya wanna be IPv6 classy)
1. a wildcard CNAME entry pointing to the A record
1. SSH server [locked to keys only](https://www.linuxbabe.com/linux-server/setup-passwordless-ssh-login) (optional, but is very good idea)

Development was done locally in lxd containers and then in Digital Ocean.

## Installing

1. SSH as root to your Ubuntu server with public IP
1. clone this repo with `git clone https://github.com/mrjones-plip/Keys-To-The-Tunnel.git`
1. `cd Keys-To-The-Tunnel` and add create `user.txt` with your github users, one per line
1. Optionally add a `logo.svg` to this directory if you want a logo to be shown on the final web page.
1. run the install script with `./installTunnelServer.sh DOMAIN.COM EMAIL` replacing `DOMAIN.COM` with your real domain from step 3 in Requirements and replacing `EMAIL` with your email which will be used to agree to Let's Encrypt TOS and to get notifications about expiring certs.
1. Send users the URL `DOMAIN.COM` which now lists how to use the server

## Using

Users should go to the website you provisioned and use the list of port/URL combos and instructions there. After that, any client that can use SSH should Just Work™.  This has been tested on Ubuntu and MacOS.

### SSH Call

The structure of the SSH call to set up the tunnel is:

`ssh -T -R PORT-FROM-SERVER:127.0.0.1:PORT-ON-LOCALHOST GH-HANDLE@DOMAIN`

### Example 1

Assuming:

* user `alligator-lovely`
* domain `tunnel.domain.com` 
* port: `4555`

If a user has a server running on `http://localhost` (implicitly port 80), they would run:

`ssh -T -R 4555:127.0.0.1:80 alligator-lovely@tunnel.domain.com`

And then in a browser they could go to `https://alligator-lovely.tunnel.domain.com`.

### Example 2

Still assuming:

* user `alligator-lovely`
* domain `tunnel.domain.com`
* port: `4555`

If a user has a server running on `https://localhost:1234`, they would run:

`ssh -T -R 4555:127.0.0.1:1234 alligator-lovely@tunnel.domain.com`

And then in a browser they could go to `https://alligator-lovely-ssl.tunnel.domain.com` - note extra `-ssl` in URL! This ensures the proxy server speaks SSL to your localhost.

## To do

- [ ] check for Nth run to not create users that already exist etc
- [ ] maybe check for Ubuntu?
- [ ] consolidate certbot calls with "-d DOMAIN" via SAN to reduce Let's Encrypt API calls?
- [ ] cache SSH keys on first validation to avoid subsequent API calls to GH to get keys again
- [ ] add redirect for bare host 80 -> 443 with HSTS, maybe do vhost instead of using default site confs?