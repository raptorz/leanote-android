# Gemsnote Mobile

珠玑笔记移动客户端，使用 Flutter 重构，同时支持 Android 和 iOS。客户端只使用已经定稿的 Gemsnote API2 v1.0.0；首次登录会从服务端建立新的 SQLite 离线缓存，不迁移旧 Android 客户端的本地数据库。

当前迁移基础已经完成：

- 旧 Android 工程完整归档到 `legacy-android/`
- 创建 Flutter Android/iOS 双平台工程
- API2 登录、服务端与最低客户端版本校验
- 笔记本、笔记正文和标签的首次全量下载
- 按“服务端地址 + 用户 ID”隔离的 SQLite 离线缓存
- token 安全存储和离线恢复登录状态
- 移动端登录、笔记本和笔记列表基础界面

迁移路线和当前边界见 [docs/MIGRATION.md](docs/MIGRATION.md)，开发环境与验证命令见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

旧版代码只作为功能和交互参考，不再继续开发，说明见 [legacy-android/README.md](legacy-android/README.md)。

本项目源自 Leanote Android 客户端，但网络、存储和界面层将由 Flutter 版本重新实现。
