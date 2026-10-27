# 真实 API2 与 PostgreSQL 联调

## 运行方式

在项目根目录运行：

```sh
bash mobile-app/scripts/test_api2_postgres.sh
```

前置依赖为已安装的 PostgreSQL 16+、Go、Python 3 和 Flutter。脚本不安装任何软件。
可用 `PG_BIN`、`GO_BIN`、`FLUTTER_BIN` 指定已有工具。

也可以使用一次性 PostgreSQL 容器，特别适用于只安装了数据库客户端的 Linux 环境：

```sh
PG_DOCKER_IMAGE=postgres:16-alpine \
FLUTTER_BIN="$HOME/develop/flutter/bin/flutter" \
bash mobile-app/scripts/test_api2_postgres.sh
```

该模式要求已有 Docker 和镜像，退出时停止本脚本创建的 `--rm` 容器；不用真实数据库。

脚本将服务端源文件复制到 `${TMPDIR:-/tmp}/gemsnote-api2-live.*`，只读取
`conf/app.conf-default`，不复制真实 `app.conf`、上传目录或修改服务端工作区。
使用随机会话密钥、独立 PostgreSQL 数据目录和内置安装种子；仅监听
`127.0.0.1:15438`（数据库）和 `127.0.0.1:19090`（API2）。
任一端口被占用时提前失败，不连接已有数据库。

测试使用该一次性环境的 `admin` / `gemsnote` 种子账号；共享测试通过管理员
用户管理 API2 添加独立接收者，不使用公开注册。
退出时停止脚本启动的服务端和数据库，保留临时目录中的日志和数据用于排查；
确认不再需要后可删除脚本输出的那个目录。不会启动 brew 常驻服务。

测试入口为 `test/live/api2_postgres_test.dart`。普通 `flutter test` 默认跳过这些
联网用例；脚本显式设置 `GEMSNOTE_DISPOSABLE_API2=1` 才运行。
客户端限制请求为指定本机地址的 `/api2/` 路径，不记录密码、token 或响应正文。
这些测试会创建笔记本、笔记和附件，不得指向真实用户数据。

只运行双客户端同步专项：

```sh
bash mobile-app/scripts/test_api2_postgres.sh --plain-name 'real API2 two-client sync'
```

## 用例边界

### 多账号离线切换与同步隔离（2026-10-20）

运行 `bash mobile-app/scripts/test_api2_postgres.sh --plain-name 'real API2 account switching'`。
真实临时服务器专项 **1 项通过**：通过生产 `AuthRepository` 登录两个账号，在同一
SQLite 数据库分别保存待同步 Markdown/富文本草稿，重建仓库对象后离线恢复与切换，
确认自动同步偏好和草稿隔离；同步 A 不清除 B 的待同步队列，各自上传到正确所有者。
双方读取对方未共享笔记均被服务端拒绝。离线退出 B 删除 B 凭据，保留 A 凭据及切换能力。
离线阶段以禁止 HTTP 的客户端及请求计数验证，不等同真实断网设备测试。

本用例使用内存凭据存储和宿主 SQLite，不声称验证设备安全存储或 UI 账号切换；
此前原生存储跨进程测试另见下文。日志 `/private/tmp/gemsnote-api2-account-isolation.log`，
临时环境 `/private/tmp/gemsnote-api2-live.6g6oZR` 已由脚本退出清理停止。

### 共享只读复制与 Bearer 认证（已修复）

运行 `bash mobile-app/scripts/test_api2_postgres.sh --plain-name 'real API2 shared note'`。
2026-10-20 最初发现的 `302 → /login` 已修复。当前移动端、联调夹具、资料修改、
图片/附件上传及共享复制均使用 Bearer 请求头，不创建 Cookie 回退会话。
token 为服务端密码学随机值并可撤销，不要求 JWT 编码。共享原文只读，复制
校验目标归属并生成独立资源，副本编辑不影响原文，撤销共享后副本仍可用。
相关测试已实际通过，旧失败记录不再作为当前阻塞项。

- 目录管理使用真实增量同步：父子笔记本创建、子目录重命名、含子目录删除拒绝、
  过期 USN 删除拒绝、删除子目录及父目录后本地目录消失。标签删除同步 tombstone，
  同时清除活动笔记和回收站笔记中的引用，保留正文和回收站状态，USN 前进。
  复现：为脚本追加 `--plain-name 'real API2 notebook and tag deletion'`。
- 使用生产 `Api2Client`、`SyncCoordinator` 和两个独立 SQLite 库验证离线创建、
  服务端上传及另一客户端增量拉取，包含中文、emoji 和 Markdown 格式。
- 通过真实 Bearer 请求上传二进制附件，再经 API2 下载并逐字节核对。
- 在服务端成功处理创建请求后主动丢弃响应；确认本地待同步记录保留，
  重试前先用另一客户端的独立缓存确认远端已经保存原 ID 与正文；
  下次同步收敛到同一笔记 ID，另一客户端只有一份对应笔记。
  这是受控的响应丢失注入，不代表真实移动弱网的所有情况。
- 后续编辑和完整历史恢复用例继续检查旧 USN 拒绝、历史正文与附件恢复。
  服务端失败时保持测试失败，不跳过内部断言或把失败算为客户端验收。
- 宿主进程联调，不代表模拟器 UI、系统后台或真机验收。

原有七项真实用例已完成验收，包括无效/已撤销 token、账号隔离、共享复制、
目录及标签管理、双客户端同步、笔记响应丢失恢复和完整历史恢复。
普通回归有条件跳过真实联网用例，不将跳过项计为通过。

## API2 1.1.0 增强专项

`real API2 creation receipts recover notebooks and safely clean unused images` 使用生产
API 客户端与 SQLite，主动丢失笔记本创建响应，验证原创建键重试和目录唯一性；
核对图片上传同键幂等、回执查询、显式重复清理、清理后的键不可复活，及当前
正文采用后、移除图片但仍有历史记录时的原件保护。安全清理不是后台扫描旧资源。

服务端另有 `TestPostgresImageUploadLifecycle`，使用独立临时 PostgreSQL
验证清理/引用竞争、所有权和旧资源保护；不能指向真实数据库。

2026-10-27：使用 `PG_DOCKER_IMAGE=postgres:16-alpine` 和独立源码副本，
真实 API2 全部 **8 项通过**。新增专项随后再次通过，包含并发创建相同键、
跨账号创建/回执/清理拒绝、tombstone 不可复活及最终上传回执响应。
服务端 PostgreSQL 原子状态测试经 `go test -race` 通过，包括唯一上传键和
24 轮引用/清理竞争。后续只要求 PostgreSQL 验收，MongoDB 支持计划移除。
测试进程和临时 API2/数据库由脚本退出清理，未连接真实服务或改动真实账号。

## Android/iOS 原生登录与进程重启

在已启动、没有重要数据的测试模拟器上运行：

```sh
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer \
  API2_IOS_SIMULATOR=<simulator-id> \
  bash mobile-app/scripts/with_xcode.sh bash mobile-app/scripts/test_api2_postgres.sh
```

Android 使用已启动的模拟器，脚本拒绝真机序列号：

```sh
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  API2_ANDROID_EMULATOR=emulator-5554 \
  bash mobile-app/scripts/test_api2_postgres.sh
```

可用 `ADB_BIN` 指定已有 adb；两个平台变量不能同时设置。
iOS 访问 `127.0.0.1:19090`，Android 使用模拟器宿主别名 `10.0.2.2:19090`，
服务端仍仅监听本机回环地址。测试客户端只允许对应地址下的 API2 请求。

此模式使用同一临时 API2 服务，依次构建运行
`integration_test/native_api2_session_test.dart` 的 seed/resume 两阶段。
第一阶段调用生产 `AuthRepository` 登录、初始化缓存、创建笔记本及离线笔记；
宿主在两阶段之间终止应用（iOS 运行器已使其退出时直接继续，其他终止错误不忽略；
Android 使用 `am force-stop`）。
第二阶段要求 PID 与第一阶段不同，禁止网络请求时
从真实 SQLite 与钥匙串恢复账号及待同步正文，再允许网络并同步验证。
随后检查未同步笔记阻止直接退出、显式退出保留修改、重新登录保留缓存并上传。

每次运行使用随机标识、独立 SQLite 文件和 `api2-device:<run>:<account>` 凭据键，
不使用正常账号数据库或凭据键。成功后删除自己的凭据和临时数据库；
失败时保留测试现场，日志只打印运行标识，不打印 token。
脚本仍会停止临时服务端与 PostgreSQL，测试失败的数据库/钥匙串夹具不可作为真实账号使用。
`--no-uninstall` 保留两个进程之间的应用容器；测试结束后需重新构建安装正常
`lib/main.dart` 应用，不能将测试入口作为普通应用使用。

这是生产仓库与原生存储的设备集成测试，不代替登录页面操作、系统后台唤醒、
跨账号切换或真机网络验收。

2026-10-20：iPhone 12 mini / iOS 26.3 两阶段均通过，各 1 项。
首阶段集成构建 268.9 秒，恢复阶段构建 60.1 秒，各阶段用例约 1 秒。
测试实际确认新 PID、离线恢复零 HTTP 请求、重连上传、退出保护与重新登录保留修改；
第二阶段结束确认测试凭据已删除、独立数据库目录已移除。
日志 `/private/tmp/gemsnote-native-api2-session.log`。

Android 35 / 一次性 Pixel 2 AVD 同样两阶段各 1 项通过（集成构建 20.5/21.1 秒，
各阶段约 1 秒），日志 `/private/tmp/gemsnote-native-api2-android-isolated.log`。
该 AVD 使用本机已有镜像、软件渲染和独立临时数据目录，没有下载镜像或清空原 AVD。
原 Pixel 9 首次在测试加载前 ADB 掉线，心跳停止；重启软件渲染后又出现启动未完成、
ADB 反复握手的环境问题。原 AVD 的失败不算业务通过，也未据此修改生产代码；
隔离环境通过不代表原 AVD 已恢复或真机验收。
原 Pixel 9 的普通 APK 恢复安装最终返回 `cmd: Can't find service: package`，
包管理服务不可用，已停止恢复尝试并保留原数据。它可能仍留有首次测试安装的集成入口；
待 AVD 正常启动后，应覆盖安装 `build/app/outputs/flutter-apk/app-debug.apk`。
隔离 AVD 已安装并启动普通 APK 后正常关闭；两者均未清空数据。

## 2026-10-20 问题复盘（均已修复）

### 上传会话认证混用

早期上传依赖 Cookie，曾因缺少浏览器请求头返回 403。临时补请求头方案已被
统一 Bearer 方案替代。现有上传/资料修改直接使用保存的 token，邮箱和密码
修改仅保留业务必要的密码确认，不再重复登录创建浏览器会话。

### PostgreSQL 历史记录字段映射

早期编辑已有历史的笔记曾返回 `historySaveFailed`，错误为：

```text
column "note_id" of relation "note_content_histories" does not exist
UPDATE note_content_histories SET histories = $1, note_id = $2, user_id = $3
WHERE user_id = $4 AND id = $5
```

`database/schema.sql` 中该表主键为 `id`。
服务端已修复 PostgreSQL 更新映射，遵循 `db`/`bson` 主键标签，使用 `id`。
新增映射回归测试；真实 PostgreSQL 已验证后续编辑、历史文件和完整恢复。
不得继续把本节历史错误当作尚未完成的服务端事项。
