`bash wechat2.sh [总实例数]`：macOS 从 `/Applications/WeChat.app` 创建第 2..N 个副本，默认 2；需要 sudo。

修改 Bundle ID/名称并临时签名，验证后移入 `/Applications`；已有副本拒绝覆盖，不自动启动。原应用和聊天数据不动；回退时移走新副本。临时签名可能影响沙盒、权限或更新，多开可用性取决于微信版本。
