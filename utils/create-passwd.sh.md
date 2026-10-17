```bash
bash utils/create-passwd.sh
bash utils/create-passwd.sh 20
```

- 依赖 Bash、tr、head、/dev/urandom；输出不含换行，传递密码时注意 shell 引号。

功能需求：
- 可选长度默认 10，范围 4..999999，仅接受无前导零的十进制整数。
- 从随机字节过滤生成密码，字符集为 23456789abcdefghijkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ 和 !@#$%^&*()+=[]{}|;:,.<>?_-。
- 整串拒绝采样，保证数字、小写、大写、符号各至少一个。
- 参数无效返回 2；随机源未提供足够字节返回 1。
