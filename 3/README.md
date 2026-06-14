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

`VPN-FILTER` на WAN-интерфейсе направляет GRE и NAT-T в IPsec. Правило `15` пропускает остальной трафик, включая первоначальный обмен IKEv2 по UDP/500. На `tunnel.0` filter-map не назначается.

## Проверка на маршрутизаторах

```text
ping 172.16.2.5
show crypto-ipsec security-association
show crypto-ipsec ike connections
show crypto-ipsec ike security-associations
show ip ospf neighbor
show ip route
show running-config
```

На BR-RTR для первой команды используйте адрес `172.16.1.4`.

Нормальное состояние IKE SA: `ESTABLISHED`. Если остаётся `CONNECTING` и `responder_spi` равен нулю, проверьте доступность WAN-адреса соседа и наличие на `int0` правил `VPN-FILTER 5`, `10` и `15`.
