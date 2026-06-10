# Отчёт: защищённый туннель HQ-RTR — BR-RTR

## Выбранное решение

Использован встроенный в EcoRouterOS IPsec с IKEv2. Существующий GRE-туннель
сохранён и защищён IPsec по схеме GRE over IPsec.

Решение выбрано потому, что GRE переносит multicast-трафик динамической
маршрутизации OSPF, а IPsec обеспечивает конфиденциальность и целостность
передаваемых пакетов.

## Основные параметры

| Параметр | Значение |
|---|---|
| Протокол согласования | IKEv2 |
| Режим IPsec | Tunnel |
| Аутентификация | Pre-shared key |
| IKE proposal | AES-256, SHA-256, MODP-2048 |
| ESP proposal | AES-256, SHA-256 |
| IKEv2 transport | NAT-T, UDP/4500, включается EcoRouter автоматически |
| Защищаемый трафик | GRE между WAN-адресами маршрутизаторов |
| GRE MTU | 1400 |
| GRE-сеть | 172.16.0.0/30 |

## Динамическая маршрутизация

Протокол OSPF продолжает работать через существующий интерфейс `tunnel1.0`.
В процесс OSPF включена GRE-сеть `172.16.0.0/30`, area 0.

Физические WAN-сети в OSPF не добавлялись. После установки IPsec SA соседство
OSPF должно восстановиться автоматически.

## Проверка

На обоих маршрутизаторах:

```text
show crypto-ipsec ike connections
show crypto-ipsec ike security-associations
show ip ospf neighbor
show ip route ospf
```

Ожидаемое состояние:

- IKE SA: `ESTABLISHED`;
- Child SA: `INSTALLED`;
- сосед OSPF: `Full`;
- удалённые сети присутствуют в таблице маршрутизации как OSPF-маршруты.
