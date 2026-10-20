# 真实 API2 与 PostgreSQL 联调

## 运行方式

在项目根目录运行：

```sh
bash mobile-app/scripts/test_api2_postgres.sh
```

前置依赖为已安装的 PostgreSQL 18、Go、Python 3 和 Flutter。脚本不安装任何软件。
可用 `PG_BIN`、`GO_BIN`、`FLUTTER_BIN` 指定已有工具。

脚本将服务端源文件复制到 `/private/tmp/gemsnote-api2-live.*`，只读取
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

只运行不依赖历史更新的两项：

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

### 共享复制的 JWT 鉴权阻塞（2026-10-20）

运行 `bash mobile-app/scripts/test_api2_postgres.sh --plain-name 'real API2 shared note'`。
测试已实际验证两个账号的共享正文读取、附件原件一致，以及接收者不能修改原文。
随后 token-only `/api2/note/copySharedNote` 返回 **302 → /login**，用例保留失败，
不会将此响应当作成功，也不增加移动端 Cookie 回退。
复制后的所有权、附件独立 ID、副本编辑不影响原文、撤销共享后副本仍可用的
断言已经编写，但尚未执行到，不能计为通过。

服务端该路由仍指向 `Note.CopySharedNote`，控制器与拦截器从 Web Session
读取用户身份；桌面端通过 `ensureSession()` 调用。修复需要真正的 JWT 鉴权入口，
并保持目标笔记本归登录者所有、源共享可读和原文只读的校验。
未获服务端修改授权，本批只修改移动端测试与文档。
管理员 Cookie 夹具仅负责临时账号和共享授权，不作为移动端业务实现。

用户明确要求 API2 统一 JWT。现有移动端 `_accountFormAction` 还用于用户名、
邮箱、密码、头像、正文图片及附件上传；这些既有 Cookie 调用也应列入后续
服务端和客户端联合整改，不能因路径以 `/api2/` 开头便宣称已统一 JWT。
需要保留敏感操作必要的密码确认，但身份认证不应因此改回 Cookie。
当前未直接删除这些功能或将其改到不存在的 token 接口。

最终复现日志 `/private/tmp/gemsnote-api2-shared-live.log`，
临时环境 `/private/tmp/gemsnote-api2-live.Zzrc1X`；进程由退出清理停止。

- 目录管理使用真实增量同步：父子笔记本创建、子目录重命名、含子目录删除拒绝、
  过期 USN 删除拒绝、删除子目录及父目录后本地目录消失。标签删除同步 tombstone，
  同时清除活动笔记和回收站笔记中的引用，保留正文和回收站状态，USN 前进。
  复现：为脚本追加 `--plain-name 'real API2 notebook and tag deletion'`。
- 使用生产 `Api2Client`、`SyncCoordinator` 和两个独立 SQLite 库验证离线创建、
  服务端上传及另一客户端增量拉取，包含中文、emoji 和 Markdown 格式。
- 通过真实 Cookie 会话上传二进制附件，再经 API2 下载并逐字节核对。
- 在服务端成功处理创建请求后主动丢弃响应；确认本地待同步记录保留，
  重试前先用另一客户端的独立缓存确认远端已经保存原 ID 与正文；
  下次同步收敛到同一笔记 ID，另一客户端只有一份对应笔记。
  这是受控的响应丢失注入，不代表真实移动弱网的所有情况。
- 后续编辑和完整历史恢复用例继续检查旧 USN 拒绝、历史正文与附件恢复。
  服务端失败时保持测试失败，不跳过内部断言或把失败算为客户端验收。
- 宿主进程联调，不代表模拟器 UI、系统后台或真机验收。

当前四项用例中，目录管理、双客户端同步/附件、创建响应丢失恢复三项已分别
在全新 PostgreSQL 库中通过；后续编辑/历史恢复一项仍受下面的服务端问题阻塞。
普通回归默认跳过四项，连同原有浏览器与性能专项共六个条件跳过项。

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

## 2026-10-20 发现的问题

### 移动端 Cookie 会话写请求

真实附件上传原先返回 HTTP 403 / `invalidRequest`。
服务端 `Api2.RequireSession` 要求写请求携带
`X-Requested-With: XMLHttpRequest`，desktop 的代理已发送该头；
移动端 `_accountFormAction` 未发送。现统一补齐 JSON、表单和 multipart
会话请求，覆盖资料修改、密码/邮箱修改、头像、正文图片和附件。
相应六类接口单元测试已加入请求头断言。

### PostgreSQL 历史记录更新阻塞

在全新安装种子库中，新建笔记、第一次历史快照及附件上传可以成功。
随后编辑该笔记时返回 `historySaveFailed`，PostgreSQL 实际错误为：

```text
column "note_id" of relation "note_content_histories" does not exist
UPDATE note_content_histories SET histories = $1, note_id = $2, user_id = $3
WHERE user_id = $4 AND id = $5
```

`database/schema.sql` 中该表主键为 `id`。
服务端 `NoteContentHistoryService.AddHistory` 更新已有快照时，经 PostgreSQL
更新字段映射产生 `note_id`。需要后续服务端修复并回归已有历史更新与完整恢复。
该问题发生在共享服务层，不能以更换移动端接口规避，也不能据此声称
desktop/Web 已实际验收。本轮没有修改服务端代码或测试库表结构。

因此，先前“完整历史恢复已实现”仍指客户端代码与模拟合同测试；
真实 PostgreSQL 后续编辑及完整恢复尚受此问题阻塞。
