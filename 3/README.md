# Модуль 3, задание 3

## 1. Установка пакетов на HQ-CLI

```bash
apt-get update
apt-get install -y expect openssh-clients sshpass
```

## 2. Настройка параметров

Проверьте адреса и учётные данные в `.env`:

```bash
HQ_SSH_HOST=172.16.4.4
BR_SSH_HOST=172.16.5.5
ROUTER_SSH_PORT=22
ROUTER_SSH_USER=net_admin
ROUTER_SSH_AUTH=password
ROUTER_SSH_PASSWORD=P@ssw0rd
```

## 3. Генерация и применение конфигурации

```bash
chmod +x 00-generate-router-configs.sh
chmod +x 01-apply-router-config.exp

./00-generate-router-configs.sh
./01-apply-router-config.exp all
```

Настройка только одного маршрутизатора:

```bash
./01-apply-router-config.exp hq
./01-apply-router-config.exp br
```

## 4. Проверка

На обоих маршрутизаторах:

```text
show crypto-ipsec ike connections
show crypto-ipsec ike security-associations
show ip ospf neighbor
show ip route ospf
```

Проверка туннеля:

```text
# HQ-RTR
ping 172.16.0.2 source 172.16.0.1

# BR-RTR
ping 172.16.0.1 source 172.16.0.2
```

Ожидаемый результат:

- IKE SA установлена;
- IPsec SA установлена;
- сосед OSPF находится в состоянии `Full`;
- удалённые сети доступны через OSPF.
