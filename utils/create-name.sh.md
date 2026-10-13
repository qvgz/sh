生成随机用户名：`bash create-name.sh [长度]`，默认 7，最少 1。输出不含换行。

依赖 Bash、`tr`、`head`、`/dev/urandom`；过滤随机字节。长度使用无前导零的十进制整数，上限 999999。
