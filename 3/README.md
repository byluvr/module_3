# Модуль 3, задание 3: GRE over IPsec

Самый простой вариант без перестройки маршрутизации — оставить существующий
GRE-туннель и OSPF, затем зашифровать GRE-трафик встроенным IPsec EcoRouter.

Чистый IPsec вместо GRE использовать нельзя: OSPF использует multicast, для
которого требуется GRE.

При IKEv2 EcoRouter автоматически включает NAT Traversal. Поэтому отдельной
команды `nat-traversal` в CLI может не быть, хотя строка отображается в
`show run`. Для входящего IKE-трафика требуется правило UDP/4500 с привязкой
к crypto-map.

## Подготовка

Проверьте `.env`:

```bash
HQ_WAN_IP=172.16.4.4
BR_WAN_IP=172.16.5.5
HQ_WAN_INTERFACE=int0
BR_WAN_INTERFACE=int0
HQ_TUNNEL_INTERFACE=tunnel.0
BR_TUNNEL_INTERFACE=tunnel.0
```

Имена WAN-интерфейсов и адреса должны совпадать с фактической конфигурацией.

После изменения `.env` создайте конфигурации заново:

```bash
bash 00-generate-router-configs.sh
```

## Настройка

На `HQ-RTR` вставьте содержимое:

```text
HQ-RTR.conf
```

На `BR-RTR` вставьте содержимое:

```text
BR-RTR.conf
```

Сначала настройте обе стороны. До завершения второй стороны GRE и OSPF могут
быть временно недоступны.

## Исправление уже введённой конфигурации

Если профиль и crypto-map уже настроены, но SA не создаётся, исправьте
filter-map.

На `HQ-RTR`:

```text
configure
no filter-map ipv4 VPN-FILTER 10
filter-map ipv4 VPN-FILTER 10
 match udp host 172.16.5.5 eq 4500 host 172.16.4.4 eq 4500
 set crypto-map VPN-MAP peer 172.16.5.5
exit
filter-map ipv4 VPN-FILTER 15
 match any any any
 set accept
exit
end
write memory
```

На `BR-RTR`:

```text
configure
filter-map ipv4 VPN-FILTER 5
 match gre host 172.16.5.5 host 172.16.4.4
 set crypto-map VPN-MAP peer 172.16.4.4
exit
no filter-map ipv4 VPN-FILTER 10
filter-map ipv4 VPN-FILTER 10
 match udp host 172.16.4.4 eq 4500 host 172.16.5.5 eq 4500
 set crypto-map VPN-MAP peer 172.16.4.4
exit
filter-map ipv4 VPN-FILTER 15
 match any any any
 set accept
exit
end
write memory
```

После этого создайте интересующий трафик:

```text
# HQ-RTR
ping 172.16.0.2 source 172.16.0.1
```

Сценарий не удаляет `tunnel.0` и не создаёт VTI. Он:

- сохраняет GRE-адреса `172.16.0.1/30` и `172.16.0.2/30`;
- устанавливает MTU `1400`;
- включает IKEv2;
- шифрует только GRE между WAN-адресами;
- добавляет служебное правило UDP/4500 для IKEv2 NAT-T;
- оставляет GRE-сеть в OSPF area 0.

## Проверка

На обоих EcoRouter:

```text
show crypto-ipsec ike connections
show crypto-ipsec ike security-associations
show ip ospf neighbor
show ip route ospf
```

Проверка связи через туннель:

```text
# HQ-RTR
ping 172.16.0.2 source 172.16.0.1

# BR-RTR
ping 172.16.0.1 source 172.16.0.2
```

В `show crypto-ipsec ike security-associations` ожидаются:

- IKE: `ESTABLISHED`;
- Child SA: `INSTALLED`.

Если IKE не поднимается, сначала проверьте обычную доступность WAN-адреса
соседа и одинаковый `IPSEC_PSK`.

Данные для отчёта находятся в `REPORT.md`.

## Важно

Если на маршрутизаторах остались объекты `VPN`, `VPN-MAP` или `VPN-FILTER`
от неудачной попытки, используйте те же имена: команды обновят их параметры.
Не применяйте одновременно старую filter-map с другим именем к `int0`.
