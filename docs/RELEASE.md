# 移动端发布

普通分支 push、PR 和手动 CI 只运行检查与测试。只有推送 `1.0.0` 这类无 `v`
的正式 tag，才执行 `.github/workflows/release.yml`。当前自动发布仅覆盖 Android；
iOS 正式签名和发布尚未实现，不发布模拟器包冒充 IPA。

## 版本与产物

版本在 `pubspec.yaml` 的 `version: 1.0.0+1` 维护：tag 对应 `1.0.0`，
`+1` 是安装包构建号。发布时递增构建号；tag 必须指向包含对应版本配置的提交。
工作流先严格校验 tag，再运行全量测试，然后用 Java 17 构建签名 Release：

- `gemsnote-<version>-android.apk`：Android 安装包。
- `gemsnote-<version>-android.aab`：应用商店上传用 bundle，不直接安装。
- `SHA256SUMS`：上述文件的 SHA-256 校验值。

构建通过后创建 GitHub Release；不会自动上传到 Google Play。
同名 Release 已存在时发布命令失败，不覆盖旧产物，也不移动 tag。
构建 artifact 保留 7 天；GitHub Release 附件不受此 artifact 保留期影响。

## Android 签名

妥善保存自己的正式 keystore；不要提交到 Git，不要使用调试密钥正式分发。
签名生成和备份要求参考 [Flutter 官方 Android 发布指南](https://docs.flutter.dev/deployment/android)。
应用更新须保持合适的签名身份，不能为每个版本生成不同的密钥。
Google Play 的应用签名密钥与上传密钥可能不同；使用上传密钥签名的 GitHub APK
不一定能覆盖安装 Play 分发版本，应事先确定分发渠道和签名方案。

在 mobile 仓库 Settings → Secrets and variables → Actions 配置：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | keystore 文件的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥密码 |

Base64 不是加密，同样必须作为 Secret 管理。工作流只在 tag 构建中将密钥解码到
runner 临时目录，构建后清理；不会把它打包进 artifact。缺失凭据或无效密钥导致失败，
不会回退到 debug 签名。尚未在本仓库远端配置或上传任何真实密钥。

## 本地构建

准备 Flutter 3.47.5、Java 17 与 Android SDK，在本仓库根目录执行检查：

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

通过本地安全方式设置以下环境变量（不要把密码写进脚本、命令历史或文档）：
`ANDROID_KEYSTORE_PATH`（keystore 绝对路径）、`ANDROID_KEYSTORE_PASSWORD`、
`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。然后执行：

```sh
flutter build apk --release --no-pub
flutter build appbundle --release --no-pub
```

输出分别是 `build/app/outputs/flutter-apk/app-release.apk` 和
`build/app/outputs/bundle/release/app-release.aab`。Gradle 不读取 `key.properties`，
只使用上述环境变量；debug 构建不需要正式签名参数。

配置签名后先本地验证，再提交版本变更并推送新 tag：

```sh
git tag -a 1.0.0 -m "Gemsnote Mobile 1.0.0"
git push origin 1.0.0
```

不要覆盖已有 tag；失败先查 Actions 日志，修复代码后使用新的版本 tag。
正式签名发布不等于功能迁移全部完成，仍需按 [迁移清单](MIGRATION.md) 进行真机验收。
