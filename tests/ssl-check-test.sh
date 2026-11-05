#!/usr/bin/env bash
# ssl-check.sh 离线测试：桩 openssl s_client 返回本地自签证书，其余子命令走真实 openssl
set -uo pipefail

script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/ops/ssl-check.sh"
t=$(mktemp -d)
trap 'rm -rf -- "$t"' EXIT
failures=0
real_openssl=$(command -v openssl)

check() {
  local name=$1 want=$2 got=$3
  if [[ $got == "$want" ]]; then echo "ok   $name"; else
    echo "FAIL $name"; diff <(echo "$want") <(echo "$got"); failures=$((failures + 1)); fi
}

mkdir -p "$t/bin" "$t/certs"
for spec in a.com:10 b.com:100; do
  "$real_openssl" req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -subj "/CN=${spec%%:*}" \
    -days "${spec##*:}" -out "$t/certs/${spec%%:*}.pem" 2>/dev/null
done
cat >"$t/bin/openssl" <<EOF
#!/usr/bin/env bash
if [[ \$1 == s_client ]]; then
  while ((\$#)); do [[ \$1 == -servername ]] && name=\$2; shift; done
  echo "\$name" >>"$t/calls"
  [[ -f $t/certs/\$name.pem ]] || exit 1
  echo CONNECTED; cat "$t/certs/\$name.pem"; exit 0
fi
exec "$real_openssl" "\$@"
EOF
chmod +x "$t/bin/openssl"
export PATH="$t/bin:$PATH" SSL_CHECK_QUERY_INTERVAL=0

d10=$(TZ=Asia/Shanghai date -d '+10 days' +%F)
d100=$(TZ=Asia/Shanghai date -d '+100 days' +%F)
check "摘要" "issuer=CN=a.com
subject=CN=a.com
notBefore=$(TZ=Asia/Shanghai date +%F)
notAfter=$d10" "$(bash "$script" A.com.)"
bash "$script" -v a.com | grep -q 'Validity'; check "-v 全文" 0 $?
bash "$script" fail.com 2>/dev/null; check "失败返回 1" 1 $?
bash "$script" 'a..com' 2>/dev/null; check "无效域名返回 2" 2 $?
bash "$script" -v -f /dev/null 2>/dev/null; check "-v 与批量互斥" 2 $?
bash "$script" -d 1234567 >/dev/null 2>&1; check "-d 超 6 位拒绝" 2 $?

: >"$t/calls"
printf '# c\n\nb.com\nA.com x\nfail.com\na.com.\nbad_domain\r\n' >"$t/list"
bash "$script" -f "$t/list" -d 30 >/dev/null; check "批量有失败返回 1" 1 $?
check "全量报告" "fail.com    X
bad_domain  X
A.com       $d10  10
a.com.      $d10  10
b.com       $d100  100" "$(cat "$t/list.check.txt")"
check "到期清单" "fail.com    X
bad_domain  X
A.com       $d10  10
a.com.      $d10  10" "$(cat "$t/list.check.30d.txt")"
check "缓存去重" "b.com
a.com
fail.com" "$(cat "$t/calls")"

if ((failures)); then echo "失败：$failures"; exit 1; fi
echo PASS
