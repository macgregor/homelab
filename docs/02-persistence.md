
1. Synology
  * set up lets encrypt cert
  * set up volumes for kubernetes, create kubernetes user for synology-csi
  * setup volume for mariadb, install mariadb, create mariadb kubernetes user and database
2. setup k3s to use mariadb
  * ssl
  * enabling statistics: https://mariadb.com/kb/en/user-statistics/ 
3. install synology-csi driver
  * synology iscsi driver suuuuucks


## LetsEncrypt, acme.sh

* there is a user defined task configured in the synology control panel that periodically runs `/var/services/homes/certadmin/cert-renew.sh`
    * this file contains passwords/api tokens
    * if encountering errors, you can edit this script and add `--debug 2` to the commands its running to get the acme script to provide more information
* theres a synology system user called "certadmin" we created in the synology control panel that is used by the script to log into the synology admin panel and update the cert when its renewed
* the scheduled tasks are being run as the root system user, if using ssh you should `sudo su` first
* acme.sh + cloudflare DNS: https://github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_cf
    * in particular `/var/services/homes/certadmin/cert-renew.sh` needs an api token/permissions from cloudflare, if something breaks with renewal its probably this authentication piece 
* upgrade the acme scripts (`sudo su` first): `/usr/local/share/acme.sh/acme.sh --force --upgrade --nocron --home /usr/local/share/acme.sh`


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

setting up nfs, dont squash permissions and grant "everyone" superduper access
https://kb.synology.com/en-us/DSM/tutorial/allow_delete_in_folder_except_one_file
