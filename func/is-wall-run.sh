#!/bin/bash
# 判断在墙内执行一组命令
# 注意：命令含有参数需要用用引号将命令和参数包裹
# 示范：is_wall_run "ls -alh /tmp" "grep 'error' /var/log/syslog"

is_wall_run() {
    # 1. 预检：如果没有参数，直接返回，避免无意义的网络请求
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    # 2. 网络探测 (Sensor)
    # -I: 仅请求 Header (减少流量)
    # -s: 静默模式 (不输出进度条)
    # --connect-timeout 3: 限制 TCP 握手时间为 3 秒
    # https://www.google.com: 标准测试靶点
    # >/dev/null 2>&1: 屏蔽所有输出
    if ! curl -Is --connect-timeout 3 https://www.google.com >/dev/null 2>&1; then

        # 3. 执行逻辑 (Actuator)
        for cmd in "$@"; do
            # 使用 eval 在当前 Shell 上下文中执行
            # 注意：必须确保传入的命令字符串是受信的，防止注入攻击
            eval "$cmd"
        done
    fi
}

is_wall_run "$@"
