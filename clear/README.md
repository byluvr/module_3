# Очистка module_3

Скрипты удаляют каталог проекта. Настроенные службы, сертификаты, логи, отчёты `PC-INFO` и `/raid/nfs/Print.pdf` сохраняются.

Запускайте нужный файл от `root` из каталога вне `module_3`:

```bash
cd /root
bash /путь/module_3/clear/01-hq-cli-clean.sh
bash /путь/module_3/clear/02-hq-srv-clean.sh
bash /путь/module_3/clear/03-br-srv-clean.sh
bash /путь/module_3/clear/04-isp-clean.sh
```
