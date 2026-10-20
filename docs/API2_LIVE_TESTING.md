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

测试仅使用该一次性环境的 `admin` / `gemsnote` 种子账号。
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
