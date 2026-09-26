# Mobile API2 与统一 UI 改造方案

本文是 Gemsnote Android（`mobile-app`）从修复版 Leanote Android 客户端改造为 Gemsnote 原生客户端的 review 和实施计划。当前阶段只完成方案，不修改业务代码。

## 1. 当前实现 Review

### 1.1 网络接口仍是旧 `/api`

`ApiProvider` 将 Retrofit 根地址固定为 `host + "/api/"`，并把 token 追加到 URL 查询参数。以下接口定义仍是旧 Leanote API：

- `AuthApi`：`auth/login`、`auth/logout`、`auth/register` 使用 GET 和 Query 参数；
- `UserApi`：`user/info`、`user/updateUsername`、`user/updatePwd`、`user/getSyncState`；
- `NotebookApi`：`notebook/getSyncNotebooks`、`getNotebooks`、`addNotebook`、`updateNotebook`；
- `NoteApi`：`note/getSyncNotes`、`getNotes`、`getTrashNotes`、`getNoteAndContent`、`addNote`、`updateNote`、`deleteTrash`、历史接口；
- `TagApi`：`tag/getSyncTags`、`addTag`、`deleteTag`；
- `NoteFileService` 和 `NoteService` 中仍直接拼接 `/api/file/getImage`、`/api/file/getAttach`；
- `strings.xml` 仍提示登录地址为 `/api/auth/login`。

这些调用必须全部切换到 `/api2`，不能只修改 Retrofit base URL，因为 API2 同时改变了部分路径、HTTP 方法和请求体语义。

### 1.2 响应和请求层仍围绕 Leanote 格式

项目使用 `LeaResponseConverter`、`LeaRequestBodyConverter` 和 `LeaFailure`，默认假设响应可以直接反序列化为旧模型，失败时再从 `Ok/Msg` 中解析错误。API2 应统一处理：

- HTTP 状态码（401、403、404、422、500）；
- `Ok:false` 和稳定错误码；
- API2 登录返回的 token、用户 ID 和用户资料；
- 空数组、分页、同步游标和历史版本的明确 JSON 结构。

模型目前主要使用大写字段（`NoteId`、`NotebookId`、`IsMarkdown` 等），这一点可以继续兼容服务端响应，但请求 DTO 不应直接复用数据库实体，避免本地字段（自增 `id`、`isDirty`、`localNotebookId`）被发送到服务端。

### 1.3 同步实现存在旧协议假设

`NoteSyncService` 和 `NoteService` 使用旧 USN 接口，按笔记本、笔记、标签分批 GET，再用旧 multipart 接口逐条上传。现有实现还存在以下改造风险：

- 本地 DBFlow 自增 ID 与服务端 MongoDB ObjectId 混用，必须明确 `serverId`/`localId` 映射；
- 笔记本、笔记、标签删除和移动的 API2 mutation 路径需要单独处理；
- 本地新建笔记上传成功后必须回写服务端 ID，不能继续使用本地 ID；
- 冲突、重试、部分失败和同步游标更新需要事务化，避免出现“游标已推进但正文未保存”；
- 头像、附件、历史正文和共享笔记不能只依赖普通笔记 USN 同步；
- 完全同步需要合并本地未上传变更与服务端快照，而不是简单覆盖本地库。

### 1.4 UI 仍是 Leanote 时代的单导航抽屉

当前 `MainActivity`、`Navigation` 和 `fragment_note.xml` 采用 Toolbar + 左侧 Drawer + 笔记列表 + FAB：

- 账号、最近笔记、笔记本和标签都在旧式抽屉中；
- 没有 Web/desktop 的全局工作区、共享入口、笔记本搜索、笔记搜索和 Info 信息区；
- 文章操作依赖菜单和 FAB，新增 Markdown/富文本、排序、星标、共享和历史入口不统一；
- 账号、设置、关于和退出的交互与当前 Web UI 不一致；
- 横屏、平板和窄屏没有按统一 UI 文档进行面板折叠。

移动端不应机械复制桌面三栏，而应采用同一信息层级的响应式变体：手机使用“工作区 → 笔记本/共享 → 笔记列表 → 编辑器”的单面板导航，平板/横屏可显示双栏或三栏。

### 1.5 安全和工程问题

`ApiProvider` 当前安装了信任所有证书的 `TrustManager`，并让 `HostnameVerifier` 永远返回 true；这会使 HTTPS 失去证书校验，不能带入正式 API2 客户端。改造时必须移除，默认使用 Android 系统证书链，开发自签名证书通过明确的 debug 配置处理。

项目仍依赖较旧的 DBFlow 4、Retrofit 2.1、RxJava 1 和 targetSdk 32。第一阶段不建议同时大规模升级依赖，但应将网络层、同步层和 UI 层解耦，为后续迁移 Kotlin/Coroutines 或 Room 留出边界。

## 2. 改造目标

1. 所有服务端请求统一使用 `/api2`，代码和资源中不再出现业务调用 `/api/`。
2. 登录时先调用 `/api2/system/version`，识别 Gemsnote 服务端和版本兼容性；404 明确提示需要迁移服务端。
3. 保持离线优先：SQLite 本地缓存、未同步队列、同步状态和多账户隔离继续有效。
4. 服务端 ID（用户、笔记本、笔记、标签、附件、历史版本）作为同步唯一标识，本地自增键只用于 SQLite 关联。
5. UI 与 Web/desktop 遵循同一 UI 层级和交互语义，移动端按屏幕尺寸采用抽屉、双栏或三栏布局。
6. 登录、退出、增量同步、完全同步、冲突、头像、附件、历史、星标、共享和搜索均有可见成功/失败反馈。

## 3. API2 接口迁移设计

### 3.1 基础传输层

新增 `Api2Client`/`Api2Error` 和统一 Retrofit 配置：

- 根地址只负责拼接服务端地址，接口路径明确写 `/api2/...`；
- 登录使用 `POST /api2/auth/login`，JSON body 为 `email`、`pwd`；
- token 由统一 Interceptor 注入。第一阶段沿用服务端当前接受的 token 机制，但集中封装，禁止业务代码自行拼接 token；
- 统一解析 HTTP 错误和 API2 `Msg` 错误码；
- 为 JSON 请求使用独立 request DTO，为 multipart 上传保留单独接口；
- 默认启用系统 TLS 校验，debug 自签名证书必须显式开关。

### 3.2 主要接口映射

| 旧调用 | API2 目标 | 改造说明 |
| --- | --- | --- |
| `auth/login` | `POST /api2/auth/login` | JSON 登录，保存 token、userId、host |
| `auth/logout` | `POST /api2/auth/logout` 或 `/api2/logout` | 注销失败也必须清除本地 token |
| `user/info` | `GET /api2/user/info` | 同步用户资料和头像 |
| `user/getSyncState` | `GET /api2/user/getSyncState` | 仅作游标/兼容信息，不替代完全同步 |
| `notebook/getSyncNotebooks` | `GET /api2/notebook/getSyncNotebooks` | 增量同步；保留 `NumberNotes` |
| `notebook/add/update/delete` | `POST /api2/client/notebook/*` 或对应 API2 路径 | 使用 JSON/明确请求 DTO |
| `note/getSyncNotes` | `GET /api2/note/getSyncNotes` | 先取元数据，再按服务端 ID 取正文 |
| `note/getNoteAndContent` | `GET /api2/note/getNoteContent` 或 `/api2/note/getNote` | 以服务端 API2 文档和响应测试为准 |
| `note/add/update/deleteTrash` | `POST /api2/client/note/*` | 新建、更新、删除、冲突和附件分开处理 |
| `tag/getSyncTags` | `GET /api2/tag/getSyncTags` | 服务端 ID 与本地映射 |
| `tag/add/delete` | `POST /api2/client/tag/*` | 不使用 GET 修改数据 |
| `note/getHistories` | `GET /api2/note/getHistories` | 历史稳定版本 ID 定位 |
| `note/getHistoryContent` | `GET /api2/note/getHistoryContent` | 按稳定 history ID 读取正文 |
| `/api/file/getImage` | `/api2/file/getImage` | 统一由 `NoteFileService` 生成 URL |
| `/api/file/getAttach` | `/api2/file/getAttach` | 附件读取和下载统一处理 |

具体请求字段以服务端 API2 文档和接口测试为准；如果 API2 client mutation 当前仍复用旧控制器的 multipart/form 解析，应在客户端封装层兼容该过渡格式，但路径不得回退到 `/api`。

## 4. 数据库和同步改造

### 4.0 参考 desktop，但不直接复制实现

可以参考 `desktop-app` 的分层和数据语义，但不能直接复用 desktop 的 SQLite 文件或 Go bridge：

- desktop 的 `db/migrations.sql`、本地/服务端 ID 映射、dirty queue、同步游标、冲突和共享笔记表结构，是移动端应保持一致的业务基线；
- mobile 当前使用 DBFlow 维护自己的 SQLite 数据库（`AppDataBase` 版本 6），与 desktop 的表名、迁移机制和字段并不兼容。第一阶段应继续使用 DBFlow，按同样的字段语义补齐迁移，不建议为了“复用”而直接替换为 desktop 的数据库文件；
- 两端可以共享一份字段/状态契约（`serverId`、`localId`、`isDirty`、`localIsNew`、同步游标等），但各自实现 repository 和 migration；后续若要跨端共享数据库，也必须先定义正式 schema 版本和迁移工具；
- desktop 的 Wails bridge 是 WebView 与 Go 服务之间的调用桥，移动端没有 Wails 运行时，不应照搬。移动端应采用 `UI → ViewModel/UseCase → Repository → API2/SQLite`，编辑器 WebView 只保留必要的 JS 回调桥；同步应由独立的 `SyncCoordinator` 驱动，而不是由 Activity 直接调用网络服务。

因此，desktop 适合作为同步规则、错误状态和 ID 语义的参考实现，不适合作为移动端代码或数据库的直接依赖。

### 阶段 A：ID 与数据模型

- 给本地实体统一增加明确的 `serverId` 字段语义，保留现有 SQLite 自增主键作为 `localId`；
- 笔记本父子关系、笔记归属、标签关系和附件关系全部通过 server ID 合并；
- 为账户保存 server URL、server user ID、API token、同步游标和最后同步状态；
- 增加 schema migration 和旧 Leanote 本地数据迁移测试。

### 阶段 B：增量同步

- 下载顺序：用户资料/头像 → 笔记本 → 笔记元数据与正文 → 标签 → 附件/历史；
- 上传顺序：笔记本 → 标签 → 笔记 → 附件，服务端返回 ID 后立即回写本地；
- 每个资源按批次提交，只有完整批次成功才推进游标；
- 失败项进入重试队列，展示“未同步”状态和错误原因；
- 对远端删除、移动、星标、回收站和共享状态做幂等合并。

### 阶段 C：完全同步和冲突

- 完全同步先获取服务端快照，再将本地未同步变更按 server ID 合并上传；
- 本地只有 local ID 的新数据走 API2 add，成功后替换为服务端 ID；
- 同一服务端/用户账户下，不覆盖本地未同步内容；冲突保留本地冲突副本并提示用户；
- 同步结束后重新计算笔记本和标签计数，清理无文章标签；
- 头像、共享笔记、附件和历史版本必须有独立验收用例。

## 5. UI 改造方案

以 `docs/development/UI.md` 的统一设计为依据，Android 采用响应式信息层级：

- 手机竖屏：顶部产品栏 + 可滑出的“我的空间”面板 + 笔记列表 + 编辑器页面；
- 平板/横屏：笔记本/共享栏、笔记列表和编辑器双栏或三栏显示；
- 顶部显示 Gemsnote/珠玑笔记标识，底部或菜单提供立即同步、账号和设置；
- “我的空间”包含笔记本树、共享笔记、标签、笔记本搜索和新增子笔记本；
- 笔记列表标题使用当前笔记本名，提供搜索、排序、星标、更新时间和同步状态；
- 编辑器标题栏提供 Info、标签、移动、分享、附件、历史、删除和 Markdown/富文本切换；
- 账号菜单包含账号、语言、同步、退出；退出只清除登录状态，不删除缓存；
- 所有加载、空状态、离线、同步成功、同步失败和权限错误都使用统一提示组件；
- 保留 Android 的触摸手势、返回键、选择/复制/粘贴和 App Widget，但不恢复博客入口。

建议先抽取 `WorkspaceState`、`SyncState` 和 `AccountState`，让 Drawer、列表和编辑器共享状态，避免继续在 Activity 之间通过隐式刷新传递数据。

### 5.1 小屏需要响应式重设计

手机小屏不能把 Web/desktop 的三栏界面等比例缩小，否则会导致笔记本树、笔记列表和编辑器同时出现时不可用。应保持相同的信息层级和操作语义，但采用移动端专门布局：

- 竖屏默认单面板：工作区/笔记本 → 笔记列表 → 编辑器，使用返回键或顶部返回按钮返回上一级；
- “我的空间”使用抽屉或底部 sheet 展开，打开笔记本后自动收起，保留当前选中状态；
- 横屏和平板再启用双栏/三栏，使用资源限定布局（`layout-sw600dp` 等）而不是运行时硬编码宽度；
- 编辑器的 Info、标签、移动、分享、附件、历史等低频操作放入顶部菜单或 bottom sheet，标题、保存/同步状态和核心编辑操作保持可见；
- 搜索、排序、星标和新增笔记必须有足够的触摸区域，并支持系统返回键、复制/粘贴和无障碍字号；
- 颜色、图标、空状态、同步提示和账号菜单沿用 Web 设计，但尺寸、手势和导航方式按 Android 规范调整。

这属于“同一设计系统的移动端变体”，不是另做一套功能；验收时应以功能和状态一致为准，以布局适配为差异。

## 6. 分阶段实施

### 第一阶段：API2 传输层和版本检测

- 建立 API2 Retrofit service、JSON DTO、统一错误处理和 token 拦截器；
- 替换登录、用户资料、登出、图片和附件 URL；
- 增加 `/api2/system/version` 检测和服务端兼容提示；
- 移除生产环境信任所有证书逻辑；
- 编写 MockWebServer/API contract 测试。

### 第二阶段：同步和本地数据

- 迁移笔记本、笔记、标签和历史接口；
- 修正 server ID/local ID 映射；
- 实现增量同步、上传队列、重试、冲突和完全同步；
- 补齐头像、附件、星标、回收站、共享笔记和历史版本；
- 用旧 Leanote 本地库和 Gemsnote 服务端做回归测试。

### 第三阶段：统一移动 UI

- 先重构主工作区和导航状态，再逐个替换笔记列表、编辑器、账号和设置页面；
- 适配手机竖屏、手机横屏、平板和深色/中文/英文环境；
- 保留 Android 原生生命周期、返回键、通知和小组件行为；
- 移除博客、主题和公开发布入口。

### 第四阶段：发布和回归

- `./gradlew test`、`./gradlew lint`、`./gradlew assembleDebug`；
- 真机验证 HTTPS、登录、离线编辑、增量/完全同步、冲突、附件、头像和分享；
- 验证旧本地 Leanote 数据迁移和新 SQLite schema 升级；
- 再更新 Android Release 和安装说明。

## 7. 验收标准

- 源码中不再有业务请求指向 `/api/`，所有服务端调用均使用 `/api2`；
- API2 404、401、403、业务错误和网络断开均有明确提示；
- 服务端、Web、desktop 与 Android 对同一用户的 ID、笔记本层级、笔记数量、星标、头像和正文一致；
- 无网络时可浏览和编辑缓存，恢复网络后可重试并清除未同步标记；
- 中文系统显示“珠玑笔记”，其它语言显示 “Gemsnote”；
- 不降低 TLS 安全性，不在日志中输出密码、token 或完整笔记正文。

## 8. 当前实施进度

已完成第一阶段的基础切换骨架：

- Retrofit 根路径切换为 `/api2/`，登录和注册改为 JSON POST；
- 增加 API2 服务版本模型和 `/api2/system/version` service；
- API2 笔记详情按 `getNote` + `getNoteContent` 两个接口读取；
- 文件和图片 URL 切换到 `/api2/file/...`；
- 更新用户名和密码改为 POST；
- 移除生产环境信任所有 TLS 证书的配置。
- 同步前刷新用户资料，确保头像和用户名进入本地缓存；
- SQLite schema 增加星标字段和 `NumberNotes` 计数字段。
- 增加完全同步入口：先上传本地变更，再重置游标并下载完整服务端数据；设置页已提供触发入口。

这部分仍需要在后续阶段补充统一错误模型、版本兼容提示、MockWebServer 契约测试以及完整同步改造。
