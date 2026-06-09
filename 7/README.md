# Модуль 3, задание 7

## 1. BR-SRV

```bash
chmod +x 01-br-srv-node-exporter.sh
./01-br-srv-node-exporter.sh
```

## 2. HQ-SRV

```bash
chmod +x 02-hq-srv-monitoring.sh
chmod +x 03-check-monitoring.sh

./02-hq-srv-monitoring.sh
./03-check-monitoring.sh
```

Скрипт автоматически добавляет в `/etc/dnsmasq.conf`:

```text
address=/mon.au-team.irpo/192.168.1.10
```

и перезапускает `dnsmasq`.

## 3. Доступ

При сохранении Apache из модуля 2:

```text
http://mon.au-team.irpo:3000
```

Учётные данные:

```text
admin
P@ssw0rd
```

Dashboard `Monitoring / AU-Team servers` содержит графики:

- загрузки CPU;
- занятой оперативной памяти;
- занятого места основного раздела `/`.

Если TCP/80 на HQ-SRV свободен, в `.env` можно указать:

```bash
GRAFANA_PORT=80
```

Тогда адрес будет `http://mon.au-team.irpo` без указания порта. DNS-запись
сама по себе не может назначить веб-сервису порт.

## 4. Проверка

На HQ-CLI:

```bash
getent hosts mon.au-team.irpo
curl -I http://mon.au-team.irpo:3000
```

На HQ-SRV:

```bash
docker compose --env-file .env -f compose.yaml ps
./03-check-monitoring.sh
```
