# Keepalived из двух НОД и проверка работоспособности сервиса СУБД MySQL
Зачастую для того, чтобы выяснить, кто из серверов в кластере отказоустойчивости должен брать на себя статус MASTER на плавающий IP-адрес, необходимо, чтобы сервер был не только доступен в сети, но и была доступность службы, с которой мы работаем. Так как предоставление конечного сервиса является ключевой задачей мониторинга сервисов.

Для примера возьмем СУБД MySQL. В конфигурационном скрипте приложения Keepalived укажем путь на BASH скрипт, который выясняет статус службы MySQL, который должен быть  **active (running)**. Где скрипт возвращает код 0 (успех) сервису keepalived, что означает успешное выполнение. Если же служба находится в статусе stop, fault, то код возврата будет 1 и приложение keepalived сочтет это за сбой работы сервиса и осуществит передачу статуса MASTER другой ноде в кластере.

Исходные данные: два сервера, на которых установлен Keepalived. Один сервер работает в роли MASTER, другой - BACKUP. На обоих серверах также стоит СУБД MySQL в режиме репликации данных и создан скрипт, который проверяет состояние службы СУБД MySQL  и передает его сервису Keepalived. 

И так, разберем код скрипта */etc/keepalived/checkactive.sh*: 
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

Если вы создаете данный скрипт в другом скрипте (например, для автоматизации деплоя) и для того чтобы результат команды не сработал (интерпритировался) во время создания скрипта и ответ не записался в тело конечного скрипта, добавьте символ экранирования \\. Как пример это используется при обозначении начала многостраничного текста Heredoc в конструкции EOF, добавьте \\ перед (systemctl is-active mysql), что будет выглядеть так:
```bash
if [ \$(systemctl is-active mysql) == "inactive" ];
```

Или используйте EOF заключенный в кавычки 'EOF', что позволит избежать интерпритации команд.


Теперь рассмотрим конфигурационный файл ноды в статусе MASTER Keepalived - */etc/keepalived/keepalived.conf*:
```bash
# primary mysql server
global_defs {
        router_id msql-01
}
# Health checks
vrrp_script chk_mysql {
        script "/etc/keepalived/checkactive.sh"  # путь до BASH  скрипта указанного выше
#       weight 2     # Вес, если есть разность приоритетов
        interval 1   # Интервал опроса
        timeout 3    # количество получения ошибок для срабатывания скрипта  
        rise 1       # количество успешных попыток для срабатывания скрипта
        }
vrrp_instance VI-MM-VIP1 {
        state MASTER
        interface enp0s8 # используемый сетевой интерфейс, который обязательно нужно подправить
        virtual_router_id 123
        priority 100 # Приоритет ноды среди нод HA-кластера
        advert_int 1
        authentication {
                auth_type PASS # Задаем данные для аунтентификации сервисов keepalived
                auth_pass pwd123
        }
        virtual_ipaddress {
                192.168.0.50 dev enp0s8 # указание публичного адреса и сетевого интерфейса на котором он создается 
        }
track_script {
    chk_mysql
  }

}
```


#### **Объяснение работы отвечающих параметров конфигурационного скрипта Keepalived указаны в комментариях к строкам**


И содержание конфигурационного файла Keepalived на второй ноде, которая выступает в роли BACKUP - */etc/keepalived/keepalived.conf*
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
        interface enp0s8 # сетевой интерфейс, который обязательно нужно подправить
        virtual_router_id 123
        priority 80 # Приоритет ноды среди нод HA-кластера ( ег оуменьшили)
        advert_int 1
        authentication {
                auth_type PASS
                auth_pass pwd123
        }
        virtual_ipaddress {
                  192.168.0.50 dev enp0s8 # указание публичного адреса и сетевого интерфейса на котором он создается 
        }
track_script {
    chk_mysql
  }

}
```


# Балансировщик нагрузки на базе Apache
Наиболее популярные  решения для создания балансировщиков нагрузки: Nginx, HaProxy, также эту функцию имеет и Apache, он конечно менее производительный чем первые два перечисленных решения. Но все же может быть удобен, если мы используем невысоконагруженный сервис в стеке, где используется Apache и мы не хотим иметь лишние установленные приложения.

Исходные данные:  два веб-сервера на базе Apache2, которые оба работают в режиме балансировщика по типу round robin и каждый второй запрос пересылают на противоположный веб-сервер. Данное решение конечно имеет свои нюансы в отказоустойчивости и дополнительно создают нагрузку на сам сервер при обработке запросов пользователей.

И так, для начала у нас должен быть установлен веб-сервер на базе Apache и также активированы его модули:
```bash
sudo apt install apache2 -y
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod lbmethod_byrequests
sudo systemctl restart apache2
```

Содержание файла конфигурации балансировщика на первом веб-сервере /etc/apache2/sites-available/balancer.conf:
```bash
<VirtualHost внешнийип-адрес-текущего-сервера:80>

    <Proxy "balancer://mycluster">
        BalancerMember http://127.0.0.1 route=web1 status=+H
        BalancerMember http://ип-адрес-2-веб-сервера route=web2 status=+H
        ProxySet stickysession=ROUTEID
    </Proxy>

    ProxyPreserveHost On
    ProxyPass / balancer://mycluster/ stickysession=ROUTEID
    ProxyPassReverse / balancer://mycluster/
</VirtualHost>
```
Содержание файла конфигурации балансировщика на втором веб-сервере /etc/apache2/sites-available/balancer.conf:
```bash
<VirtualHost внешнийип-адрес-текущего-сервера:80>

    <Proxy "balancer://mycluster">
        BalancerMember http://127.0.0.1 route=web1 status=+H
        BalancerMember http://ип-адрес-1-веб-сервера route=web1 status=+H
        ProxySet stickysession=ROUTEID
    </Proxy>

    ProxyPreserveHost On
    ProxyPass / balancer://mycluster/ stickysession=ROUTEID
    ProxyPassReverse / balancer://mycluster/
</VirtualHost>
```

После чего на каждом веб-сервере применяем файл конфигурации веб-сервера balancer.conf и перезагружаем службу веб-сервера

```bash
sudo a2ensite balancer.conf
sudo a2dissite 000-default.conf
sudo systemctl restart apache2
```
