#!/usr/bin/env bash
# 域名 IP

function get_domain_ip(){
  # dig $1 @1.0.0.1 | grep -E '^[^;;]*IN*A*' | head -n 1 | awk '{print $5}'
  dig +short @1.0.0.1 $1 | head -n1
}
get_domain_ip $1
