# 服务端待修复与三端联合处理清单

记录日期：2026-10-20。用户要求本批仅记录，后续服务端、Web、desktop、mobile
联合处理。以下均未修复；本批不修改服务端或桌面端。

## S01：API2 统一 JWT 鉴权

API2 路径不代表已经采用 JWT。当前一部分路由复用 Web 控制器和 Cookie Session，
导致客户端需要重复建立会话。目标是受保护 API2 业务接口统一使用 JWT 身份；
公开找回密码、公开头像等既定匿名能力另行明确，不应强行要求登录。

### 已定位接口

| 接口 | 当前实现/问题 | 后续处理 |
| --- | --- | --- |
| `POST /api2/note/copySharedNote` | `Note.CopySharedNote` 依赖 Session；真实 token 请求 302 到 `/login` | JWT 身份复制；目标笔记本必须归当前用户，源笔记必须仍可读 |
| `POST /api2/user/updateUsername` | `User.UpdateUsername`；移动端临时 Cookie 会话 | 改为 JWT 身份更新 |
| `POST /api2/web/emailChange` | `Web.EmailChange`；移动端临时 Cookie 会话 | 提供明确的 JWT 账号接口，保留必要密码确认和邮箱验证 |
| `POST /api2/user/updatePwd` | `User.UpdatePwd`；移动端临时 Cookie 会话 | JWT 身份，保留旧密码确认，明确密码变更后的 token 失效规则 |
| `POST /api2/avatar` | `Api2.UploadAvatar`；移动端临时 Cookie 会话 | JWT multipart 上传，保留大小/类型及所属用户校验 |
| `POST /api2/file/pasteImage` | `File.PasteImage`；移动端临时 Cookie 会话 | JWT multipart 上传，只允许写当前用户笔记 |
| `POST /api2/attachments/upload` | `Api2.UploadAttachment`；移动端临时 Cookie 会话 | JWT multipart 上传，保留笔记归属、文件和历史快照校验 |

这是已定位清单，不是服务端全部接口审计结论。联合处理时需遍历 `conf/routes`
全部 `/api2/` 路由及鉴权拦截器，覆盖附件删除/下载、分享授权、管理员接口等其他
复用 Web 控制器的入口。管理员权限仍须独立验证；不得恢复公开注册。

定位参考（相对服务端根目录）：

- `conf/routes`：混合路由。
- `app/controllers/BaseController.go`：`GetUserId` 读取 `Session["UserId"]`。
- `app/controllers/init.go`：`AuthInterceptor` 检查会话，否则返回 NOTLOGIN 或重定向。
- `desktop-app/webapi/local.go`：`copySharedNote` 调用 `Proxy.ensureSession()`。
- `mobile-app/lib/core/api/api2_client.dart`：复制使用 token；资料和上传使用 `_accountFormAction`。

### 三端配合与验收

1. 服务端统一 JWT 验证和当前用户上下文；明确缺失、过期、撤销 token 的 JSON
   错误契约，不返回 HTML 或重定向登录页。不能仅增加 `X-Requested-With` 掩盖鉴权差异。
2. Web 同步适配登录、请求封装、退出及会话失效；明确 token 存储与发送方式。
   原 Web 页面会话是否保留应与 API2 业务认证分开设计，不能先删除而使现有 Web 失效。
3. desktop 移除这些业务操作的 `ensureSession()` 依赖；mobile 移除相应
   `_accountFormAction` 和仅为换 Cookie 而出现的密码输入。敏感操作的业务密码确认保留。
4. 共享原文统一只读，只有原作者可以编辑。副本必须新建 ID 并归接收者所有；
   图片、附件归属与访问权限独立，编辑副本不改变原文，撤销共享不破坏已完成的副本。
5. 用实际服务端验证三端：有效/缺失/过期 token、跨账号资源拒绝、只读共享、
   复制与附件、退出失效、重复提交/响应丢失。不要依赖 Mock 通过宣称联调完成。

现成回归：`scripts/test_api2_postgres.sh --plain-name 'real API2 shared note'`
（从项目根目录加 `mobile-app/` 前缀）。该用例目前真实失败于 302；
复制后的断言尚未执行到。管理员 Cookie 测试夹具仅用于初始化测试数据，
不是移动端业务回退方案；统一接口后应同步调整夹具。

## S02：PostgreSQL 历史更新字段映射错误

实际 `note_content_histories` 主键列为 `id`，但后续历史快照更新生成
`SET ... note_id=...`，PostgreSQL 报该列不存在，笔记修改返回 `historySaveFailed`。
这不是只影响 mobile 的数据层问题：其他端只要触发同一历史更新路径也存在风险；
尚未逐端实际复现，不把风险判断写成三端测试结果。

定位：`app/db/postgres_codec.go` 的 `postgresUpdateMap` / `buildPostgresSet`，
以及 `NoteContentHistoryService.AddHistory` 的结构体更新路径。

后续修复应统一结构体字段与数据库列映射，不通过给测试库添加 `note_id` 绕过。
增加结构体更新及连续历史写入回归；实际验证多次编辑、上传附件后的编辑、
历史列表和恢复（正文、格式、附件集合），并核对 Web/desktop/mobile。
现有 `test/live/api2_postgres_test.dart` 历史用例保留真实失败，修复后重跑完整临时库套件。

## 证据与范围

- 本批共享合同回归 13 项通过；普通执行时 5 项真实联网测试按条件跳过。
- 静态分析通过。真实共享测试失败日志：`/private/tmp/gemsnote-api2-shared-live.log`。
- 复现、临时环境限制及历史错误详见 [API2_LIVE_TESTING.md](API2_LIVE_TESTING.md)。
- 尚未修复或宣称迁移全部完成；发布仍暂缓。
