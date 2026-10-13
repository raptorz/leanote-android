# Android 分享接收

`MainActivity` 接收 `ACTION_SEND` / `ACTION_SEND_MULTIPLE` 的文本、图片和附件（通配 MIME）。支持 `EXTRA_TEXT` 单项/列表，以及 `EXTRA_STREAM` 或 ClipData 中的文件 URI。纯文本和 Markdown 文件严格按 UTF-8 解码；其余内容按二进制原件保存。

- 每批最多 8 项，持久收件箱总容量也是 8 项，文本单项最多 256 KiB UTF-8，二进制单文件最多 32 MiB。私有分享暂存目录总量最多 96 MiB（含正在读取的文件），超限拒绝，不淘汰待导入原件。
- 文件只从 `content://` URI 读取；Android 检查来源授予的 URI 读取权限。
  拒绝应用自身的 provider，不能从外部分享入口读取应用内部文件。
- 不需要存储/媒体读取权限，不保存长期 URI 授权，也不读取任意文件路径。
- `SharedTextDecoder` 严格验证 UTF-8、拒绝 NUL/空白/非法编码，支持 UTF-8 BOM，
  保留正文和换行，不执行或下载正文链接。标题限制按 Unicode 码点计算。
- 文件在最多 2 个后台 worker 中读取；每批 15 秒后提示超时并拒绝迟到结果。
  无响应 provider 的系统 I/O 不保证立即中止，其 worker 位置在实际返回前仍占用，
  避免无界线程/任务增长。普通文本接收不依赖文件 worker。
- 同一批全部读取和验证成功后，才在主线程检查最新队列剩余容量并一次 commit。
  任一文件失败、超限或容量不足，整批不新增记录。文件附带的 `EXTRA_TEXT`
  作为独立待导入文本保留，也计入容量，避免静默丢弃说明文字。
- 二进制文件以随机 ID 存在私有 `filesDir/shared_resources`，不使用来源文件名构造路径。文件 fsync 完成后才能入队；导入确认后移除原件，下次初始化或入队清理无队列引用且不在读取中的残留文件。
- Flutter 只在用户选择账号后按 ID/accountKey 读取已认领原件，并验证长度；笔记与待上传任务同一数据库事务保存，失败全部回滚，不提前 acknowledge。PNG/JPEG 可规范化为正文图片，或取消勾选保留为普通附件。未联网、不自动上传；后续上传复用 API2 和资源队列。
- 稳定 ID 在读取前生成；打开工作区后，沿用账号/笔记本确认、claim、
  本地幂等导入、acknowledge 和 API2 同步。切换账号不自动改投已绑定分享。
- Activity 重建不重放已接收 intent；读取完成时通知当前 Flutter engine。
  保存成功前进程若被系统杀死，未完成的读取不能保证恢复，需要来源重新分享；
  成功提示只在本机队列持久写入完成后显示。

## 验证

```sh
bash scripts/test_android_share_decoder.sh
```

脚本使用 `JAVA_HOME`，未设置时使用 Android Studio 自带 JDK；编译生产 Java 解码器和资源暂存模块。
覆盖 UTF-8/BOM、多字节跨块、恰好达限/超限、无限长度流读取界限、来源读取失败、
中断、NUL/空白和 Unicode 标题；资源测试覆盖二进制保真、重开读取、路径拒绝、空/超限文件、总容量、取消清理和读取期间的残留清理互斥。Android debug APK 构建验证 Kotlin/Java 集成和 Manifest。

尚待设备验收：来源应用 URI 授权、冷/热启动、文件选择器和云端 provider、
多项与混合说明文字、满队列、超时、后台/旋转/进程终止、与导入确认同时读取文件。
JVM 测试及 APK 编译不代表上述设备用例已通过。

接口依据：[Android 接收其他应用分享](https://developer.android.com/develop/ui/compose/sharing/receive)。
