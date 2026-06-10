# Централизованный rsyslog

Проверьте адрес HQ-SRV, порт, протокол и размер ротации в `.env`.

## HQ-SRV

```bash
chmod +x ./*.sh ./*.exp
./01-hq-srv-rsyslog-server.sh
```

## BR-SRV

```bash
./02-br-srv-rsyslog-client.sh
```

## HQ-CLI

```bash
apt-get install -y expect openssh-clients sshpass
./03-generate-router-configs.sh
./04-apply-router-config.exp all
```

## Проверка на HQ-SRV

```bash
ss -lntup | grep ':514'
find /opt -maxdepth 2 -type f -ls
```

HQ-SRV не должен создавать каталог логов для самого себя.
