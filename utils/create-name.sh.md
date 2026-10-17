```bash
bash utils/create-name.sh
bash utils/create-name.sh 12
```

- 依赖 Bash、tr、head、/dev/urandom；输出不含换行。

功能需求：
- 可选长度默认 7，范围 1..999999，仅接受无前导零的十进制整数。
- 从随机字节过滤生成用户名，字符集为 23456789abcdefghijkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ。
- 参数无效返回 2；随机源未提供足够字节返回 1。
