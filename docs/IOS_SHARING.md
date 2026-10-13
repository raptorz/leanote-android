# iOS 分享接收

当前实现单项纯文本与 HTTP(S) 网页链接接收。文件、图片和多项接收仍待迁移。
这是原生 Share Extension，不依赖 Flutter 引擎在后台运行，也不在扩展内登录或联网。

## 使用流程

1. 在其他应用的系统分享面板选择 Gemsnote，确认或编辑文本后保存。
2. 打开 Gemsnote；工作区初始化或回到前台时读取收件箱。
3. 点击待处理分享，确认服务器、账号、笔记本后导入，也可明确丢弃。
4. 本地导入成功后才移除收件记录。后续上传沿用现有 API2 同步。

扩展不会自动启动主应用。队列最多 8 项，每项文本最多 256 KiB UTF-8；
满队列、无效输入、读取失败或存储失败会提示，不能以分享完成掩盖写入失败。
未知/多个输入不截断导入。网页链接按文本保存，不自动访问目标。

## 工程和签名

- Runner 依赖并嵌入 `ShareExtension.appex`，扩展仅使用原生框架。
- Runner bundle ID 为 `com.github.gemsnote`，扩展为 `com.github.gemsnote.ShareExtension`。
- 两个 target 的 Debug/Release/Profile 共用 `Shared/AppGroup.entitlements`，
  App Group 来自项目级 `GEMSNOTE_APP_GROUP`，默认 `group.com.github.gemsnote`。
- 在 Apple Developer 账号中注册相应 App Group，把两个 App ID 都加入该组，
  并为两个 target 配置同一开发团队和支持该权限的 provisioning profile。
  使用自有 bundle ID 时也需配置匹配的扩展 ID 和有权使用的 App Group。
- 两个 Info.plist 的 `GemsnoteAppGroup` 与 entitlement 使用相同 build setting；
  扩展版本从 Flutter Generated.xcconfig 读取，与主应用一致。
- 扩展不共享 token、密码或 Keychain。导入账号由主应用确认后绑定；
  已绑定条目不能因切换账号而被改投，稳定记录 ID 复用现有幂等导入。

`Shared/SharedTextStore.swift` 使用 App Group 内独立锁文件和 `flock`，
在锁内读取、校验、修改并原子替换 JSON。损坏的收件箱保留原文件并报错。
队列文件使用首次解锁后的数据保护。主应用方法通道在隐式 Flutter engine 初始化时注册。

## 验证

macOS Command Line Tools 即可运行存储测试：

```sh
bash scripts/test_ios_share_store.sh
```

它编译生产存储源码，验证持久化、容量和字节限制、账号绑定、幂等、损坏数据保护，
并启动 8 个独立进程验证并发写入不丢记录。Flutter 的
`test/shared_text_inbox_test.dart` 覆盖 Android/iOS 默认启用和初始化/前台刷新路径。

这些检查不能替代 iOS 编译与真机验收。当前机器只有 Command Line Tools，
没有完整 Xcode；UIKit/Social 类型检查、模拟器/真机、签名和归档尚未验证。
安装完整 Xcode 后需检查：

- Debug 模拟器构建及 Release/Profile 扩展嵌入、签名、版本一致性。
- Safari 网页和其他应用纯文本；冷启动、未登录、后台到前台。
- 取消、编辑、读取失败、超时、超限、满队列、系统终止扩展后重试。
- 不同账号间切换、导入后确认失败重试、重复点击不产生重复笔记。
- 扩展与主应用同时保存/确认、设备锁定与解锁后的数据保护行为。
- 文件/图片/多项应不显示为支持，若来源仍提供此类输入应明确拒绝。

实现依据：[Apple 扩展共享数据](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html)、
[Apple 激活规则](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html)、
[Flutter UIScene 与隐式引擎通道注册](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)。
