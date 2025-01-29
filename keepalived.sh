#!/bin/bash
# MUST TUNE VAR
IPMYSQLSERVER1="192.168.56.147" # ip address mysqserver 1
IPMYSQLSERVER2="192.168.56.146" # ip address mysqserver 2
VIPPUBLICMYSQL="192.168.56.150/24" # public vip keepalived mysql service
DEVINTERFACE="enp0s8" # net device interface

# configure keepalived.conf on MASTER
bash -c "cat <<EOIPFW >> /etc/keepalived/keepalived.conf
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
        interface $DEVINTERFACE
        virtual_router_id 123
        priority 100
        advert_int 1
        authentication {
                auth_type PASS
                auth_pass pwd123
        }
        virtual_ipaddress {
                $VIPPUBLICMYSQL dev $DEVINTERFACE # public interface for VIP
        }
track_script {
    chk_mysql
  }

}
EOIPFW"

# create  bash script checkactive.sh for keepalived mysql check
cat <<EOF > /etc/keepalived/checkactive.sh
#!/bin/bash
# Название службы MySQL, обычно это mysql или mysqld
# Проверка статуса службы
 
if [ \$(systemctl is-active mysql) == "inactive" ];
then
# Возвращаем код выхода 1, если служба неактивна
exit 1
else
# Возвращаем код выхода 0 (нет ошибки), если служба активна
echo 0
fi
EOF
chmod +x /etc/keepalived/checkactive.sh
# create keepalived user for script
useradd -s /usr/sbin/nologin keepalived_script 
echo 'net.ipv4.ip_nonlocal_bind=1' | sudo tee --append /etc/sysctl.conf > /dev/null
sysctl -p
systemctl start keepalived
