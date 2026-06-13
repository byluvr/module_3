# HTTPS и центр сертификации

Проверьте домены, адреса, SSH-порты и срок сертификатов в `.env`.

## ISP

```bash
chmod +x ./*.sh
./00-isp-prepare.sh
```

## HQ-SRV

```bash
./01-hq-srv-issue-certificates.sh
```

## ISP

```bash
./02-isp-nginx-https.sh
```

## HQ-CLI

```bash
./03-hq-cli-trust-ca.sh
```

## Проверка

```bash
curl -I https://web.au-team.irpo/
curl -I https://docker.au-team.irpo/
```
