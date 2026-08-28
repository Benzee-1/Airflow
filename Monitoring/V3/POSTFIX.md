# Postfix local

Alertmanager résout `host.docker.internal` vers la passerelle de l'hôte. Postfix doit donc écouter sur une adresse que le bridge Docker peut joindre, pas uniquement sur 127.0.0.1.

Exemple conceptuel à adapter à la politique locale dans `/etc/postfix/main.cf` :

```ini
inet_interfaces = loopback-only, 10.240.129.104
mynetworks = 127.0.0.0/8, 172.16.0.0/12
smtpd_recipient_restrictions = permit_mynetworks,reject
```

Ne pas ouvrir le port 25 aux autres réseaux. Restreindre `mynetworks` au subnet Docker réellement retourné par `docker network inspect airflow3-monitoring_monitoring`.

Validation :

```bash
postfix check
systemctl reload postfix
ss -lntp | grep ':25'
printf 'Subject: test Postfix SID1

OK
' | sendmail -v airflow-ops@example.org
docker run --rm --add-host host.docker.internal:host-gateway alpine sh -c 'nc -vz host.docker.internal 25'
```
