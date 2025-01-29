# Keepalived и проверка работоспособности сервиса СУБД MySQL
Зачастую для того, чтобы выяснить, кто из серверов в кластере отказоустойчивости должен брать на себя статус MASTER на плавающий IP-адрес, необходимо, чтобы сервер был не только доступен в сети, но и была доступность службы, с которой мы работаем. Так как предоставление конечного сервиса является ключевой сутью мониторинга сервисов.

Для примера возьмем СУБД MySQL. В конфигурационном скрипте приложения Keepalived укажем путь на BASH скрипт, который выясняет статус службы MySQL, который должен быть  **active (running)**. Где скрипт возвращает код 0 (успех) сервису keepalived, что означает успешное выполнение. Если же служба находится в статусе stop, fault, то код возврата будет 1 и приложение keepalived сочтет это за сбой работы сервиса и осуществит передачу статуса MASTER другой ноде в кластере.

И так, разберем код скрипта /etc/keepalived/checkactive.sh: 
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

Если вы создаете данный скрипт в другом скрипте (например, для автоматизации деплоя), для обозначения начала многостраничного текста Heredoc в конструкции EOF добавьте символ экранирования \\, что будет выглядеть так:
```bash
if [ \$(systemctl is-active mysql) == "inactive" ];
```

Теперь рассмотрим конфигурационный файл Keepalived - /etc/keepalived/keepalived.conf:
```bash
# primary mysql server
global_defs {
        router_id msql-01
}
# Health checks
vrrp_script chk_mysql {
        script "/etc/keepalived/checkactive.sh"
#       weight 2     # Is relevant for the diff in priority
        interval 1   # every ... seconds
        timeout 3    # script considered failed after ... seconds
        fall 3       # number of failures for K.O.
        rise 1       # number of success for OK
        }
vrrp_instance VI-MM-VIP1 {
        state MASTER
        interface enp0s8 # LAN interface VM
        virtual_router_id 123
        priority 100
        advert_int 1
        authentication {
                auth_type PASS
                auth_pass pwd123
        }
        virtual_ipaddress {
                192.168.0.50 dev enp0s8 # public interface for VIP
        }
track_script {
    chk_mysql
  }

}
```

И содержание конфигурационного файла Keepalived на второй ноде, которая выступает в роли BACKUP - /etc/keepalived/keepalived.conf
```bash
# primary mysql server
global_defs {
        router_id msql-01
}
# Health checks
vrrp_script chk_mysql {
        script "/etc/keepalived/checkactive.sh"
#       weight 2     # Is relevant for the diff in priority
        interval 1   # every ... seconds
        timeout 3    # script considered failed after ... seconds
        fall 3       # number of failures for K.O.
        rise 1       # number of success for OK
        }
vrrp_instance VI-MM-VIP1 {
        state BACKUP
        interface enp0s8
        virtual_router_id 123
        priority 80
        advert_int 1
        authentication {
                auth_type PASS
                auth_pass pwd123
        }
        virtual_ipaddress {
                  192.168.0.50 dev enp0s8 # public interface for VIP
        }
track_script {
    chk_mysql
  }

}
```
