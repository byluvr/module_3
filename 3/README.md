# GRE over IPsec

На HQ-CLI установите зависимости:

```bash
apt-get update
apt-get install -y expect openssh-clients sshpass
chmod +x ./*.sh ./*.exp
```

Проверьте WAN-адреса, интерфейсы и SSH-доступ в `.env`, затем:

```bash
./00-generate-router-configs.sh
./01-apply-router-config.exp all
```

`VPN-FILTER` используется на WAN-интерфейсе только для направления GRE в IPsec. На `tunnel.0` он не назначается и пользовательский трафик не фильтрует.

## Проверка на маршрутизаторах

```text
show crypto-ipsec security-association
show ip ospf neighbor
show ip route
show running-config
```
