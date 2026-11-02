```bash
bash ops/wechat2.sh
bash ops/wechat2.sh 3
```

- 仅 macOS，源应用为 /Applications/WeChat.app，需要 sudo、ditto、codesign、xattr、PlistBuddy。
- 临时签名可能影响沙盒、权限和更新，多开效果取决于微信版本；中途失败可能留下已完成副本，回退时自行移走副本。
- 更新时旧副本程序被替换删除；用户数据在 ~/Library/Containers/<Bundle ID>，Bundle ID 不变故保留。重签名后系统权限（摄像头、麦克风等）可能需重新授权。

功能需求：
- 可选总实例数 2..99，默认 2；生成 /Applications/WeChat2.app 至 WeChatN.app，已有目标为符号链接或正在运行则拒绝。
- 复制源应用，Bundle ID 追加序号，修改应用及简体中文名称，清除隔离属性，执行临时签名并验证。
- 验证后移入 /Applications，已有副本先移出再替换（覆盖更新程序），不自动启动；原应用和聊天数据不修改，退出清理暂存目录。
