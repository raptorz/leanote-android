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

## Markdown 阅读

Markdown 阅读使用 [flutter_markdown_plus](https://pub.dev/packages/flutter_markdown_plus)
原生组件，并保留可复制的原文模式。个人笔记图片由账号隔离的缓存组件处理；
未缓存时由用户手动点击、经 API2 校验后下载，不启用渲染器默认的网络/本地文件加载。
共享、历史及编辑预览中的图片仍为占位。链接仅展示地址并允许用户复制。
此实现不支持 Markdown 中内嵌 HTML 的浏览器渲染，富文本笔记继续使用原有阅读组件。

## 原文导出

`NoteExporter` 调用已锁定依赖版本的 `FilePicker.saveFile`，使用返回的 URI 判断
是否保存，取消返回 null；不把 Android content URI 当作本地路径写文件。
测试可注入保存回调验证字节、文件名、取消和失败行为。导出不执行 HTML，也不下载附件。
iOS 保存对话框只能在 macOS/iOS 环境完成构建和真机验收。

图片预览通过 `ImageExporter` 复用系统文件保存能力和文件名清理逻辑，只保存已读取的
图片字节，不再请求服务器。输出扩展名和 MIME 由 PNG/JPEG/GIF/WebP 文件头确定，
不信任服务端文件名或类型；仍限制每张最多 8 MiB。该检查只识别格式，图片解码验证
由读取图片的仓储层负责。导出到系统文件后不再受账号缓存清理控制，用户自行管理。

## 附件保存

普通附件通过 `/api2/note/getNote` 校验个人笔记归属与文件成员后，调用
`/api2/file/getAttach`，不使用正文 URL。该接口错误也可能返回 HTTP 200，
因此必须同时检查 `Content-Disposition: attachment`，不能把 JSON/登录页当附件保存。
下载不跟随重定向，响应头限时 30 秒、响应体总限时 60 秒，大小上限 32 MiB；
完整下载到内存后才打开系统保存窗口，空附件允许保存。文件名来自已校验的列表并清理路径字符，
忽略响应头文件名；原始字节不执行、不自动打开，不写入离线缓存。

## 测试原则

- API 客户端测试必须检查 HTTP 方法、路径和 JSON 请求体
- SQLite 测试使用内存数据库，不依赖真实用户数据
- 同步测试需要覆盖分页、超时、原子提交、ID 映射和账号隔离
- 提交前至少运行 `flutter analyze` 和 `flutter test`
