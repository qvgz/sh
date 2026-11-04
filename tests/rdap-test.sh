#!/usr/bin/env bash
# rdap.sh 离线测试：用桩 whois/curl 替代网络
set -uo pipefail

script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/ops/rdap.sh"
t=$(mktemp -d)
trap 'rm -rf -- "$t"' EXIT
failures=0

check() {
  local name=$1 want=$2 got=$3
  if [[ $got == "$want" ]]; then echo "ok   $name"; else
    echo "FAIL $name"; diff <(echo "$want") <(echo "$got"); failures=$((failures + 1)); fi
}

future=$(date -d '+10 days' +%F)
far=$(date -d '+100 days' +%F)
mkdir -p "$t/bin"
# whois：仅 a.com 有到期字段
cat >"$t/bin/whois" <<EOF
#!/usr/bin/env bash
case \$1 in
  a.com) printf 'Registry Expiry Date: ${future}T00:00:00Z\nCreation Date: 2000-01-01T00:00:00Z\nName Server: NS1.A.COM\nName Server: NS2.A.COM\n' ;;
  *) echo 'No match' ;;
esac
EOF
# curl：IANA 列表 + RDAP 响应；fail.com 返回 errorCode
cat >"$t/bin/curl" <<EOF
#!/usr/bin/env bash
url=\${*: -1}; out=
while ((\$#)); do [[ \$1 == -o ]] && out=\$2; shift; done
case \$url in
  *dns.json) echo '{"services":[[["com"],["http://bad/","https://r1/","https://r2/"]]]}' >"\$out" ;;
  https://r1/domain/b.com) echo '{"objectClassName":"domain","events":[{"eventAction":"expiration","eventDate":"${far}T00:00:00Z"}],"nameservers":[{"ldhName":"ns.b.com"}]}' ;;
  https://r*/domain/fail.com) echo '{"errorCode":404}' ;;
  *) exit 22 ;;
esac
EOF
chmod +x "$t/bin/"*
export PATH="$t/bin:$PATH" RDAP_QUERY_INTERVAL=0

check "whois 摘要" "expiration	$future
registration	2000-01-01
nameservers	NS1.A.COM" "$(bash "$script" https://www.A.com:443/x)"
check "rdap 回退" "expiration	$far
nameservers	ns.b.com" "$(bash "$script" b.com)"
bash "$script" fail.com 2>/dev/null; check "失败返回 1" 1 $?
bash "$script" 'a..com' 2>/dev/null; check "无效域名返回 2" 2 $?
check "大写协议头" "$(bash "$script" a.com)" "$(bash "$script" HTTPS://WWW.A.COM/)"
bash "$script" -d 1234567 >/dev/null 2>&1; check "-d 超 6 位拒绝" 2 $?

printf '# c\n\nb.com\nwww.a.com x\nfail.com\na.com\nbad_domain\n' >"$t/list"
bash "$script" -f "$t/list" -d 30 >/dev/null; check "批量有失败返回 1" 1 $?
check "全量报告" "fail.com    X
bad_domain  X
www.a.com   $future  10
a.com       $future  10
b.com       $far  100" "$(cat "$t/list.check.txt")"
check "到期清单" "fail.com    X
bad_domain  X
www.a.com   $future  10
a.com       $future  10" "$(cat "$t/list.check.30d.txt")"

if ((failures)); then echo "失败：$failures"; exit 1; fi
echo PASS
