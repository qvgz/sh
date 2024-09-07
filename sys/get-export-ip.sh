#!/usr/bin/env bash
# 出口 IP
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/sys/get-export-ip.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/sys/get-export-ip.sh)"

function get_local_ip(){
    export_ip=""

    if [[ ! -p /tmp/export-ip ]];then
          mkfifo -m 777 /tmp/export-ip
     fi

     while [[ ! $export_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]];do
          case $((RANDOM%6+1)) in
               1)
                    query_export_ip_api="https://api.ipify.org"
               ;;
               2)
                    query_export_ip_api="https://ip.3322.net"
               ;;
               3)
                    query_export_ip_api="https://ifconfig.me"
               ;;
               4)
                    query_export_ip_api="http://ip.sb"
               ;;
               5)
                    query_export_ip_api="https://checkip.amazonaws.com"
               ;;
               6)
                    query_export_ip_api="http://whatismyip.akamai.com"
               ;;
          esac
          (
               export_ip=$(curl -s $query_export_ip_api)
               echo "$export_ip" > /tmp/export-ip &
          )
          read -r export_ip < /tmp/export-ip
     done
     echo $export_ip
}
get_local_ip
