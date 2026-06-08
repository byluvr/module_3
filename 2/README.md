# Модуль 3, задание 2: ГОСТ CA и HTTPS

Используется ГОСТ Р 34.10-2012 с хешем ГОСТ Р 34.11-2012. Серверный
сертификат выдаётся на `30` дней и содержит оба DNS-имени:

- `web.au-team.irpo`;
- `docker.au-team.irpo`.

## Параметры

Перед запуском проверьте `.env`, особенно:

```bash
CERT_DAYS=30
CA_DAYS=30
GOST_CIPHERS=GOST2012-GOST8912-GOST8912:GOST2001-GOST89-GOST89
ISP_IP=172.16.1.1
HQ_CLI_IP=192.168.2.10
WEB_UPSTREAM=172.16.1.2:8080
DOCKER_UPSTREAM=172.16.2.2:8080
```

## 1. Подготовка ISP

На `ISP`:

```bash
bash 00-isp-prepare.sh
```

Скрипт устанавливает nginx, SSH и `openssl-gost-engine`, создаёт
`sshuser` и включает поддержку ГОСТ.

## 2. Выпуск и передача сертификатов

На `HQ-SRV`:

```bash
bash 01-hq-srv-issue-certificates.sh
```

Центр сертификации сохраняется в:

```text
/root/au-team-ca
```

Скрипт автоматически передаёт:

- сертификат и ключ веб-сервера на `ISP`;
- корневой сертификат на `HQ-CLI`.

## 3. HTTPS на ISP

На `ISP`:

```bash
bash 02-isp-nginx-https.sh
```

HTTP-запросы перенаправляются на HTTPS. Basic Auth остаётся включён только
для `web.au-team.irpo`.

Закрытый ключ устанавливается с правами `0600`:

```text
/etc/nginx/ssl/web.key
```

## 4. Доверие на HQ-CLI

На `HQ-CLI`:

```bash
bash 03-hq-cli-trust-ca.sh
```

Сценарий устанавливает `chromium-gost`, включает ГОСТ в OpenSSL и помещает
сертификат в системное хранилище:

```text
/etc/pki/ca-trust/source/anchors/au-team-ca.crt
```

Для проверки используйте Chromium GOST. Обычная сборка браузера может не
поддерживать ГОСТ-наборы TLS. Если Chromium GOST был открыт, перезапустите
его.

## Проверка

На `HQ-CLI`:

```bash
curl -I https://web.au-team.irpo/
curl -u 'WEB:P@ssw0rd' https://web.au-team.irpo/ | head
curl https://docker.au-team.irpo/ | head
```

Параметр `-k` использовать нельзя: проверка должна проходить через
установленный доверенный CA.

В браузере откройте:

```text
https://web.au-team.irpo/
https://docker.au-team.irpo/
```

Предупреждений о сертификате быть не должно. Для `web.au-team.irpo`
используются логин `WEB` и пароль `P@ssw0rd`.

Проверка алгоритма и срока на `HQ-SRV`:

```bash
openssl x509 -in /root/au-team-ca/web.crt -noout -text
openssl x509 -in /root/au-team-ca/web.crt -noout -dates
```
