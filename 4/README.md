# Межсетевой экран EcoRouter

На HQ-CLI проверьте WAN-адреса, внутренние сети, интерфейсы и разрешённые порты в `.env`.

```bash
apt-get update
apt-get install -y expect openssh-clients sshpass nmap
chmod +x ./*.sh ./*.exp
./00-generate-router-configs.sh
./01-apply-router-config.exp all
```

## Проверка с ISP

```bash
nmap -Pn -p 22,80,443,8080,2026,5555 172.16.1.4
nmap -Pn -p 22,80,443,8080,2026,5555 172.16.2.5
nmap -Pn -sU -p 53,123,9999 172.16.1.4
nmap -Pn -sU -p 53,123,9999 172.16.2.5
```

Разрешённый порт может быть `open` или `closed`. Не разрешённый порт должен быть `filtered`.
