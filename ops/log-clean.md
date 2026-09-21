# 日志清理

需求描述：
  - log-clean.sh <log_dir> [run_cmd]
    - log_dir 日志路径
      - 路径不存在退出脚本
    - run_cmd 日志处理后需要执行命令
      - run_cmd 存在且 run_cmd_test=true，处理日志前先执行该命令，错误输出退出脚本
  - 备份日志：
    - 创建备份目录 "$log_dir/backup/$(date -d "yesterday" +%Y%m%d)"
    - 使用 find 移动 "$log_dir/*.log" 到备份目录
    - run_cmd 存在执行
  - 清理日志：
    - 清理 "$log_dir/backup/"，保留 backup_day 天
    - 清理日志使用 ionice -c3
    - 删除 "$log_dir/backup/" 空目录
    
