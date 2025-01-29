# Keepalived и проверка работоспособности сервиса СУБД MySQL
Зачастую для того, чтобы выяснить, кто из серверов в кластере отказоустойчивости должен брать на себя статус MASTER на плавающий IP-адрес, необходимо, чтобы сервер был не только доступен в сети, но и была доступность службы, с которой мы работаем. Так как предоставление конечного сервиса является ключевой сутью мониторинга сервисов.

Для примера возьмем СУБД MySQL. В конфигурационном скрипте приложения Keepalived укажем путь на BASH скрипт, который выясняет статус службы MySQL, который должен быть  **active (running)**. Где скрипт возвращает код 0 (успех) сервису keepalived, что означает успешное выполнение. Если же служба находится в статусе stop, fault, то код возврата будет 1 и приложение keepalived сочтет это за сбой работы сервиса и осуществит передачу статуса MASTER другой ноде в кластере.

И так, разберем код скрипта: 
```bash
#!/bin/bash
# Название службы MySQL, обычно это mysql или mysqld
# Проверка статуса службы
if [ $(systemctl is-active mysql) == "inactive" ];
then
# Возвращаем код выхода 1, если служба неактивна
exit 1
else
# Возвращаем код выхода 0 (нет ошибки), если служба активна
echo 0
fi
```

Если вы создаете данный скрипт в другом скрипте (например, для автоматизации деплоя), для обозначения начала многостраничного текста Heredoc в конструкции EOF добавьте символ экранирования \, что будет выглядеть так:
```bash
if [ \$(systemctl is-active mysql) == "inactive" ];
```
