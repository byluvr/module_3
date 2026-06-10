# Prometheus и Grafana

DNS-запись `mon.au-team.irpo` создаётся Samba-скриптом `module_2/1`. Скрипты мониторинга не изменяют `dnsmasq` на HQ-SRV.

Проверьте адреса, порты и пароль Grafana в `.env`.

## BR-SRV

```bash
chmod +x ./*.sh
./01-br-srv-node-exporter.sh
```

## HQ-SRV

```bash
./02-hq-srv-monitoring.sh
```

## Проверка с HQ-CLI

```bash
./03-check-monitoring.sh
```

Откройте `http://mon.au-team.irpo:3000`, логин `admin`, пароль из `.env`.
