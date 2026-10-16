# dns-web-mail-server

Author: Esther Blessing Durojaye Platform: KodeKloud playground, CentOS Stream 9 Date: 16 October 2026

1. Objective

Set up three core network services and prove each one works:

Service	Software	Role
DNS server	BIND 9.16 (named)	Resolves lab.local names, MX record and reverse lookups
Web server	Nginx 1.20	Serves a test web page
Mail server	Postfix 3.5 + Dovecot 2.3	Sends and stores mail (SMTP) and serves it to users (IMAP)
2. Architecture

All three services run on one CentOS Stream 9 machine (private IP 10.244.49.2). DNS names stand in for separate hosts:

Name	Points to	Purpose
dns1.lab.local	10.244.49.2	Name server (NS)
web1.lab.local	10.244.49.2	Web server
www.lab.local	CNAME to web1	Web alias
mail1.lab.local	10.244.49.2	Mail server
mail.lab.local	CNAME to mail1	Mail alias
lab.local (MX)	mail1.lab.local, priority 10	Mail routing

Two test users, alice and bob, hold mailboxes in Maildir format.

Design note: the original plan was three separate EC2 instances on AWS (dns1, web1, mail1 with fixed private IPs). That could not be completed because the AWS account could not be activated, and the first KodeKloud AWS sandbox was terminated by its session timer. The build was therefore done on a single KodeKloud CentOS machine. The configuration for each service is the same as it would be on separate hosts, and only the IP addresses differ.

3. Environment limits
The lab has no systemd, so systemctl and hostnamectl do not work. Services were started directly (named, nginx, postfix start, dovecot).
The hostname was set with hostname mail1.lab.local.
The lab resets when its timer ends, so everything is scripted in setup.sh.
4. Build steps
4.1 Install packages
bash
sudo dnf install -y bind bind-utils nginx postfix dovecot s-nail iproute nmap-ncat
4.2 DNS (BIND)
/etc/named.conf defines the options (listen on 127.0.0.1 and 10.244.49.2, recursion enabled for local use) and declares two zones.
/var/named/lab.local.zone is the forward zone (A, CNAME, NS and MX records).
/var/named/10.244.49.rev is the reverse zone for 49.244.10.in-addr.arpa (PTR records).
Configuration was validated with named-checkconf and named-checkzone, then BIND was started with named -u named.
/etc/resolv.conf was pointed at 127.0.0.1 so the machine uses its own DNS server.
4.3 Web (Nginx)
Test page written to /usr/share/nginx/html/index.html.
Configuration checked with nginx -t, then started with nginx.
4.4 Mail (Postfix + Dovecot)
Postfix set with postconf -e: myhostname = mail1.lab.local, mydomain = lab.local, home_mailbox = Maildir/, inet_protocols = ipv4, mynetworks = 127.0.0.0/8.
Users alice and bob created with passwords.
Dovecot set to mail_location = maildir:~/Maildir, with plaintext auth and SSL disabled (lab only, never for production).
5. Test results
Test	Command	Result
Zone files load	named-checkzone	Both zones loaded, OK
Forward lookup	dig @127.0.0.1 www.lab.local +short	web1.lab.local. and 10.244.49.2
System resolver uses BIND	dig mail1.lab.local +short	10.244.49.2
Web server	curl -H "Host: www.lab.local" http://127.0.0.1	<h1>web1.lab.local is up</h1>
Nginx config	nginx -t	Syntax OK, test successful
Postfix running	postfix status	Running
Mail delivery	bob sends to alice, then ls /home/alice/Maildir/new	Message file present
IMAP login and read	nc 127.0.0.1 143 session	Logged in, 1 EXISTS, body Hello Alice, this is a test

Screenshots: add them to a screenshots/ folder and reference them here.

6. Troubleshooting log
Problem	Cause	Fix
ping, ip and hostname not found	Minimal lab image	Installed iproute and used dig for tests
hostnamectl failed with "not booted with systemd"	No systemd in the lab	Used hostname directly and started services by hand
Dovecot would not start (missing dovecot.pem)	10-ssl.conf references a certificate that does not exist	Commented out ssl_cert, ssl_key and ssl_dh in 10-ssl.conf
Mail stuck in the queue: alias database unavailable	Postfix aliases database was not built	Ran newaliases, postfix reload, postqueue -f
Some package downloads returned HTTP 403	One mirror refused requests	dnf fell back to another mirror automatically
7. Limitations
Single machine, so this does not show network separation between roles.
Not reachable from the internet, so the web page cannot be opened by an outside browser. Evidence is the screenshots and command output above.
Plaintext IMAP with no TLS and a weak lab password are for the lab only. A production server needs TLS certificates, authenticated submission on port 587, SPF, DKIM and DMARC records, and a matching reverse DNS (PTR) record.
8. Files in this repo
setup.sh: rebuilds the whole lab on a fresh CentOS Stream 9 machine. It was assembled from the commands run manually and has not been run end to end in one pass.
configs/: copies of named.conf, the two zone files, postconf -n output and 99-lab.conf.
screenshots/: proof of each test.
