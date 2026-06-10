# CUPS PDF-принтер

Проверьте имя сервера, IP, порт и имена очередей в `.env`.

## HQ-SRV

```bash
chmod +x ./*.sh
./01-hq-srv-cups.sh
```

## HQ-CLI

```bash
./02-hq-cli-printer.sh
lpstat -t
```

## HQ-SRV после печати

```bash
./03-hq-srv-export-pdf.sh
ls -l /raid/nfs/Print.pdf
```
