# 移动端开发

## 环境

- Flutter stable 3.47 或更高版本
- Android SDK（最低系统版本跟随当前 Flutter stable）
- Android Studio 或支持 Flutter 的编辑器
- iOS 构建需要 macOS、Xcode 和 CocoaPods

中国大陆网络可使用：

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

## 常用命令

```sh
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

iOS 工程只能在 macOS 上构建：

```sh
flutter build ios
```

## 服务端要求

客户端要求 Gemsnote API2 v1.0.0。登录接口 `/api2/auth/login` 一次返回 token、用户资料和服务端版本；旧 `/api` 与旧 Leanote 服务端不在支持范围内。

首次登录按 USN 分页下载笔记本、含正文笔记和标签，并在单个 SQLite 事务中替换该账号快照。token 只在完整快照成功落库后写入系统安全存储，避免残缺缓存被当成有效登录。

## 测试原则

- API 客户端测试必须检查 HTTP 方法、路径和 JSON 请求体
- SQLite 测试使用内存数据库，不依赖真实用户数据
- 同步测试需要覆盖分页、超时、原子提交、ID 映射和账号隔离
- 提交前至少运行 `flutter analyze` 和 `flutter test`
