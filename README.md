# Gemsnote Android

Gemsnote（珠玑笔记）安卓客户端，基于原 [Leanote Android](https://github.com/leanote/leanote-android)（Leamonax）修改开发，与 Gemsnote 服务端及 Gemsnote Desktop 功能对齐。

# 中文README
[README_ZH](README-zh.md)

# 功能

- [x] 登录 / 注册，多账户切换，自定义服务器地址
- [x] 笔记本、笔记增量同步（USN）
- [x] Markdown 与富文本编辑器
- [x] 标签：随同步自动更新，支持按标签筛选，长按删除标签
- [x] 回收站：查看已删除笔记、还原、彻底删除
- [x] 历史版本：在线读取服务端版本列表（保留最近 20 份），离线时回退到本地内容快照，可随时回看与还原
- [x] 附件：查看笔记附件列表，下载并打开
- [x] 标题搜索与全文搜索（FTS）
- [x] 桌面小组件

# 构建

```bash
./gradlew assembleDebug
```

默认 applicationId 为 `com.github.gemsnote`，应用名称为 `Gemsnote`（中文环境显示「珠玑笔记」）。

# 服务端

需要连接 Gemsnote 服务端（或兼容 Leanote API 的私有部署）。登录时填写服务器地址，例如 `https://your-server.com`。

# Contributors

- [houxg](https://github.com/houxg)
- [xingstarx](https://github.com/xingstarx)
- [nicacol](https://github.com/nicacol)
- [Ericwyn](https://github.com/Ericwyn)
- [binsheng](https://github.com/binsheng)
