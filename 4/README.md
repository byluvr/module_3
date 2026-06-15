# Межсетевой экран EcoRouter

Выполняется на HQ-CLI после настройки VPN из `module_3/3`.

```bash
apt-get update
apt-get install -y expect openssh-clients sshpass nmap
chmod +x ./*.sh ./*.exp
./00-generate-router-configs.sh
./01-apply-router-config.exp all
```

Фильтр назначается только на WAN-интерфейс `int0`. На `tunnel.0` правила не назначаются.

Проверка VPN и OSPF:

```text
show crypto-ipsec ike security-associations
show ip ospf neighbor
show ip route ospf
```

Проверка доступа к репозиторию с HQ-SRV, HQ-CLI и BR-SRV:

```bash
curl -I http://ftp.altlinux.org/
apt-get update
```

Проверка с ISP:

```bash
nmap -Pn -p 22,8080,2026,5555 172.16.1.4
nmap -Pn -p 22,8080,2026,5555 172.16.2.5
nmap -Pn -sU -p 53,123,9999 172.16.1.4
nmap -Pn -sU -p 53,123,9999 172.16.2.5
```

Порт `5555/tcp` и `9999/udp` должны быть `filtered`.
