```bash
bash utils/unixtime.sh
bash utils/unixtime.sh -m
bash utils/unixtime.sh 1700000000
bash utils/unixtime.sh 1700000000123
```

- 依赖 Bash、GNU/BSD date；格式化使用本地时区，日期范围由系统 date 决定。BSD 当前毫秒以 000 填充，没有真实毫秒精度。

功能需求：
- 无参数输出当前秒时间戳；-m 输出当前毫秒时间戳。
- 一个整数参数按秒格式化为 YYYY-MM-DD HH:MM:SS，支持负数秒。
- 恰好 13 位非负整数视为毫秒时间戳，前 10 位按秒格式化并追加 .后三位。
- 多参数或其他输入返回 2，日期转换失败返回非零。
