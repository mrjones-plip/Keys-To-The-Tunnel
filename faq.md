# FAQ

### Where does the name "Keys-To-The-Tunnel" come from?
Keys-To-The-Tunnel is named after the fact that it uses SSH tunnels and the keys for this are pivotal to why it exists: easily provision accounts from GH users based off their SSH keys.

### Wait...why not ansible, saltstack etc.?
It started as "just a quick bash script" and then spiraled out of control from there.  Sorry!

### How come I'm getting 400 errors in Apache `The plain http request was sent to https port`?
A user has created an SSH tunnel using the non-ssl vhost in the top group of port/URL sets which points to a web server running SSL on localhost.  Have them use the `-ssl` vhost listed in the bottom group of port/URL sets.  The reason is that the Apache vhost has a hard coded proxy of either `ProxyPass / http://localhost:PORT/` or `ProxyPass / https://localhost:PORT/`, it can't be both.  
  
### Why not use [ngrok](https://ngrok.com/), [pagekite](https://pagekite.net/), [localtunnel](https://github.com/localtunnel/localtunnel) or InsertSolutionHere instead?
You totally can!  These are much more full featured and are much easier to use. [localtunnel](https://github.com/localtunnel/localtunnel)  may be of particular interest as it has a self hosted option.  Conversely, they cost more money this this script.  It's estimated a $5/mo VPS could support dozzens of users. This solution also offers authentication in the way of SSH keys. Finally, this script makes it trivially easy to provision users because the accounts are tied to GitHub.
  
### Does this work with self-signed certs on localhost?
Yes! Apache is intentionally configured to ignore all certificate errors. Traffic sent between the remote web server and the localhost is sent securely over SSH, so there should be no security concerns about using self signed certs here.
  

### A user having trouble setting up the tunnel - how can test using their account?
If the user is named `alligator-lovely`, open `/home/alligator-lovely/.ssh/authorized_kes` and add your public SSH key on a new line.  This way you can SSH in to remove any doubt that the server is working correctly.
  

### I need to add more users after setting this up a first time - can I re-run the script?
Yes, the script is safe to re-run multiple times. Edit the `user.txt` file to only have the new users.
  

### A user changed their SSH key on GitHub - how do I update their account?
Edit the `user.txt` file to only have the one user.  They will lose their original port mapping and get a new one.


### How do I get a list of all the users in my GH org?
Get a [personal GH token](https://github.com/settings/tokens), then call the [list org members API](https://docs.github.com/en/rest/reference/orgs#list-organization-members) with this call `curl -H "Authorization: token  TOKEN" https://api.github.com/orgs/ORG/members`. Be sure to replace `TOKEN` and `ORG` with your token and your org. There's rate limits, but [at 5000/hr](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting), they probably don't apply.


### Is there a rate limit to the number of Let's Encrypt certs I can request?
Yes! It's [50/week](https://letsencrypt.org/docs/rate-limits/).  This script should really be using Subject Alternative Name (SAN) mechanism...[hopefully soon](https://github.com/mrjones-plip/Keys-To-The-Tunnel/issues/1)! 

Until then, if you have less than 50 users you're onboarding per day, you're fine. Each user gets two domains and both are done in a single call with 2 SANs.

### I added a GH user, but it doesn't create an account for them, why not?
All users must have an SSH key on GH.  Check `https://github.com/USERNAME.keys` and ensure a key is listed there. Re-run the script if need be after a key has been added by the user.
