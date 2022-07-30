
1. Synology
  * set up lets encrypt cert
  * set up volumes for kubernetes, create kubernetes user for synology-csi
  * setup volume for mariadb, install mariadb, create mariadb kubernetes user and database
2. setup k3s to use mariadb
  * ssl
3. install synology-csi driver

Resources:
* https://dr-b.io/post/Synology-DSM-7-with-Lets-Encrypt-and-DNS-Challenge
* https://www.cyberciti.biz/faq/issue-lets-encrypt-wildcard-certificate-with-acme-sh-and-cloudflare-dns/
* https://github.com/SynologyOpenSource/synology-csi
* https://github.com/christian-schlichtherle/synology-csi-chart
* https://rene.jochum.dev/rancher-k3s-with-galera/ (only somewhat applicable)

```
$ ssh macgregor@synology

# login as root mysql user using the admin password configured in DSM
$ mysql -u root -p
Enter password:

MariaDB [(none)]> CREATE DATABASE `kubernetes`;
MariaDB [(none)]> CREATE user 'kubernetes'@'%' IDENTIFIED BY 'password';
MariaDB [(none)]> GRANT ALL PRIVILEGES ON `kubernetes`.* TO 'kubernetes'@'%';
```




```

# run with --test first to verify

export CF_Token="redacted"
acme.sh --issue -d matthew-stratton.me -d *.matthew-stratton.me -w /tmp/mnt/1.44.1-42218/www --server letsencrypt --dns dns_cf

acme.sh --install-cert -d matthew-stratton.me \
--fullchain-file /tmp/mnt/1.44.1-42218/cert/matthew-stratton.me/fullchain.pem \
--key-file /tmp/mnt/1.44.1-42218/cert/matthew-stratton.me/key.pem \
--reloadcmd "service nginx restart"
chown root:nobody -R /tmp/mnt/1.44.1-42218/cert/matthew-stratton.me/
chmod -R 0640 /tmp/mnt/1.44.1-42218/cert/matthew-stratton.me/


export SYNO_Username="certadmin"
export SYNO_Password='redacted'
export SYNO_Certificate="Let's Encrypt"
export SYNO_Create=1
export CF_Token="kaCSPkFUWo3qnpDUT0i5qEYNL9hgF6Fu1E8DfEYn"


export SYNO_Username="certadmin"
export SYNO_Password='redacted'
export SYNO_Certificate="synology.matthew-stratton.me"
export SYNO_Create=1
export SYNO_Scheme="https"
export SYNO_Host="localhost"
export SYNO_Port="5001"
export CF_Token="redacted"
export CF_Email="matthew.m.stratton@gmail.com"

/usr/local/share/acme.sh/acme.sh --renew -d "$SYNO_Certificate" \
  --home /usr/local/share/acme.sh && \
/usr/local/share/acme.sh/acme.sh --deploy -d "$SYNO_Certificate" \
   --deploy-hook synology_dsm \
   --reloadcmd "/usr/local/bin/reload-certs.sh" \
   --dnssleep 20 \
   --home /usr/local/share/acme.sh

/usr/local/share/acme.sh/acme.sh --server letsencrypt --issue \
  -d "$SYNO_Certificate" \
  -d "auth.matthew-stratton.me" \
  -d "sso.matthew-stratton.me" \
  -d "ldap.matthew-stratton.me" \
  -d "maraidb.matthew-stratton.me" \
  -d "nfs.matthew-stratton.me" \
  --home /usr/local/share/acme.sh \
  --dns dns_cf


  /usr/local/share/acme.sh &&
  /usr/local/share/acme.sh/acme.sh -d $SYNO_Certificate --deploy \
     --deploy-hook synology_dsm \
     --reloadcmd "/usr/local/bin/reload-certs.sh" \
     --dnssleep 20 \
     --home $PWD

./acme.sh -d "synology.matthew-stratton.me" -d "www.synology.matthew-stratton.me" --deploy --deploy-hook synology_dsm --home $PWD
```

setting up nfs, dont squash permissions and grant "everyone" superduper access
https://kb.synology.com/en-us/DSM/tutorial/allow_delete_in_folder_except_one_file
