#!/bin/bash
# setup.sh - DNS (BIND), web (Nginx), mail (Postfix + Dovecot) for lab.local
# Target: fresh CentOS Stream 9 lab without systemd.
# Assembled from the commands run manually; not yet run end to end in one pass.
set -e
sudo dnf install -y bind bind-utils nginx postfix dovecot s-nail iproute nmap-ncat

IP=$(ip -4 addr show eth0 | awk '/inet /{print $2}' | cut -d/ -f1)
IFS=. read a b c d <<< "$IP"
REV="$c.$b.$a.in-addr.arpa"
sudo hostname mail1.lab.local

# --- DNS ---
sudo tee /etc/named.conf >/dev/null <<EOF
options {
    directory "/var/named";
    listen-on port 53 { 127.0.0.1; $IP; };
    allow-query { any; };
    recursion yes;
    allow-recursion { 127.0.0.1; $IP; };
    dnssec-validation no;
    pid-file "/run/named/named.pid";
};
zone "." IN { type hint; file "named.ca"; };
zone "lab.local" IN { type master; file "lab.local.zone"; };
zone "$REV" IN { type master; file "lab.rev"; };
EOF
sudo tee /var/named/lab.local.zone >/dev/null <<EOF
\$TTL 3600
@     IN SOA dns1.lab.local. admin.lab.local. (2026101601 3600 900 604800 3600)
@     IN NS  dns1.lab.local.
dns1  IN A   $IP
web1  IN A   $IP
mail1 IN A   $IP
www   IN CNAME web1
mail  IN CNAME mail1
@     IN MX 10 mail1.lab.local.
EOF
sudo tee /var/named/lab.rev >/dev/null <<EOF
\$TTL 3600
@ IN SOA dns1.lab.local. admin.lab.local. (2026101601 3600 900 604800 3600)
@ IN NS  dns1.lab.local.
$d IN PTR mail1.lab.local.
$d IN PTR web1.lab.local.
$d IN PTR dns1.lab.local.
EOF
sudo chown root:named /var/named/lab.local.zone /var/named/lab.rev
sudo mkdir -p /run/named && sudo chown named:named /run/named
sudo named-checkconf
sudo named-checkzone lab.local /var/named/lab.local.zone
sudo named -u named -c /etc/named.conf
echo -e "nameserver 127.0.0.1\nsearch lab.local" | sudo tee /etc/resolv.conf

# --- Web ---
echo "<h1>web1.lab.local is up</h1>" | sudo tee /usr/share/nginx/html/index.html
sudo nginx -t && sudo nginx

# --- Mail ---
sudo postconf -e "myhostname = mail1.lab.local"
sudo postconf -e "mydomain = lab.local"
sudo postconf -e 'myorigin = $mydomain'
sudo postconf -e 'mydestination = $myhostname, $mydomain, localhost'
sudo postconf -e "mynetworks = 127.0.0.0/8"
sudo postconf -e "inet_interfaces = all"
sudo postconf -e "inet_protocols = ipv4"
sudo postconf -e "home_mailbox = Maildir/"
for u in alice bob; do
  id $u &>/dev/null || sudo useradd -m $u
  echo "$u:Lab12345!" | sudo chpasswd
done
sudo newaliases
sudo postfix start

printf 'mail_location = maildir:~/Maildir\ndisable_plaintext_auth = no\nssl = no\n' | sudo tee /etc/dovecot/conf.d/99-lab.conf
sudo sed -i -E 's/^(ssl_cert|ssl_key|ssl_dh)/#\1/' /etc/dovecot/conf.d/10-ssl.conf
sudo mkdir -p /run/dovecot
sudo dovecot

# --- Tests ---
dig www.lab.local +short
dig MX lab.local +short
dig -x "$IP" +short
curl -s -H "Host: www.lab.local" http://127.0.0.1
echo "Hello Alice, this is a test" | s-nail -s "Lab test" -r bob@lab.local alice@lab.local
sleep 3; sudo ls /home/alice/Maildir/new
