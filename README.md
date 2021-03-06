#  Keys-To-The-Tunnel
 
## Intro

Keys-To-The-Tunnel is for when you have a lot of GitHub Developers who have added their SSH key to GitHub (e.g. [here's mine](https://github.com/mrjones-plip.keys)) and they also are doing local development of apps that they either need to share with others via the internet or they need valid TLS certificates to test with, or both!

The script will:
1. Create an SSH login on the host
1. Lock this login to only allow SSH tunnels
1. Create an Apache vhost for this login, with the `GH-USERNAME.domain.com`
1. Create an SSL certificate with Let's Encrypt for `GH-USERNAME.domain.com`
1. Put instructions to use the SSH tunnels at `domain.com`

Keys-To-The-Tunnel is named after the fact that it uses SSH tunnels and the keys for this are pivotal to why it exists: easily provision accounts from GH users based off their SSH keys.

This script is [hosted on GitHub](https://github.com/mrjones-plip/mrjones-medic-scratch/tree/main/SshTunnelServer).

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

## todo

- [ ] check for Nth run to not create users that already exist etc
- [ ] maybe check for ubuntu?
- [ ] consolidate certbot calls with "-d DOMAIN" via SAN to reduce API calls?
- [ ] cache SSH keys on first validation to avoid subsequent API calls to GH to get keys again
- [ ] add redirect for bare host 80 -> 443 with HSTS, maybe do vhost instead of using default site confs?
- [ ] group more domains in SAN calls to void going over 50certs/day Let's Encrypt limit

## FAQ

Click a question to see the answer:

<details>
    <summary> Wait...why not ansible, saltstack etc.?</summary>

It started as "just a quick bash script" and then spiraled out of control from there.  Sorry!
</details>

<details>
    <summary> How come I'm getting 400 errors in Apache `The plain http request was sent to https port`?</summary>

A user has created an SSH tunnel using the non-ssl vhost in the top group of port/URL sets which points to a web server running SSL on localhost.  Have them use the `-ssl` vhost listed in the bottom group of port/URL sets.  The reason is that the Apache vhost has a hard coded proxy of either `ProxyPass / http://localhost:PORT/` or `ProxyPass / https://localhost:PORT/`, it can't be both.  
</details>
  

* **Q:** Why not use [ngrok](https://ngrok.com/), [pagekite](https://pagekite.net/), [localtunnel](https://github.com/localtunnel/localtunnel) or InsertSolutionHere instead?
  
  **A:** You totally can!  These are much more full featured and are much easier to use. [localtunnel](https://github.com/localtunnel/localtunnel)  may be of particular interest as it has a self hosted option.  Conversely, they cost more money this this script.  It's estimated a $5/mo VPS could support dozzens of users. This solution also offers authentication in the way of SSH keys. Finally, this script makes it trivially easy to provision users because the accounts are tied to GitHub.
  

* **Q:** Does this work with self-signed certs on localhost?
  
  **A:** Yes! Apache is intentionally configured to ignore all certificate errors. Traffic sent between the remote web server and the localhost is sent securely over SSH, so there should be no security concerns about using self signed certs here.
  

* **Q:** A user having trouble setting up the tunnel - how can test using their account?
  
  **A:** If the user is named `alligator-lovely`, open `/home/alligator-lovely/.ssh/authorized_kes` and add your public SSH key on a new line.  This way you can SSH in to remove any doubt that the server is working correctly.
  

* **Q:** I need to add more users after setting this up a first time - can I re-run the script?
  
  **A:** Yes, the script is safe to re-run multiple times. Edit the `user.txt` file to only have the new users.
  

* **Q:** A user changed their SSH key on GitHub - how do I update their account?
  
  **A:** Edit the `user.txt` file to only have the one user.  They will lose their original port mapping and get a new one.


* **Q:** How do I get a list of all the users in my GH org?
  
  **A:** Get a [personal GH token](https://github.com/settings/tokens), then call the [list org members API](https://docs.github.com/en/rest/reference/orgs#list-organization-members) with this call `curl -H "Authorization: token  TOKEN" https://api.github.com/orgs/ORG/members`. Be sure to replace `TOKEN` and `ORG` with your token and your org. There's rate limits, but [at 5000/hr](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting), they probably don't apply.


* **Q:** Is there a rate limit to the number of Let's Encrypt certs I can request?
  
  **A:** Yes! It's [50/week](https://letsencrypt.org/docs/rate-limits/).  This script should really be using Subject Alternative Name (SAN) mechanism...hopefully soon!
  

* **Q:** I added a GH user, but it doesn't create an account for them, why not?
  
  **A:** All users must have an SSH key on GH.  Check `https://github.com/USERNAME.keys` and ensure a key is listed there. Re-run the script if need be after a key has been added by the user.
