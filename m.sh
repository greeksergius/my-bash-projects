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
