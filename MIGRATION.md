# Flutter 持续迁移进度

本文件为长期目标的恢复入口。详细历史实现说明保留在 [docs/MIGRATION.md](docs/MIGRATION.md)，开发细节见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。不能把历史勾选项等同于整体验收。

## 约束及范围

- 主工作目录保持服务端仓库根目录。所有 Git 操作明确使用 `git -C mobile-app`；只提交此独立仓库的相关文件，不 push、不改写历史。
- 服务端、desktop-app、legacy-android 仅作只读参考，不修改。主 Agent 顺序执行。
- 业务通信必须为 API2。用户已明确允许公开头像直接访问；沿用同源、不携带凭据、不跟随重定向的下载策略。
- 用户确认 Android 和 iOS 都需要分享功能（发送与接收）；iOS Share Extension 属于目标。
- 服务端修改不属于本次目标。确认缺口后记录具体需求，交由后续处理，不回退 Legacy API。
- 旧 Android 小组件保留为目标。深链、生物识别属于既有规划扩展，是否为旧功能对应项还需核对，不能冒充已迁移。
- 注册、博客、演示账号、旧数据库迁移目前按原迁移方案排除；若发现与必要移动功能有依赖需重新记录。

## 当前现场（2026-10-12）

- 独立仓库已确认：`/Users/raptor/Documents/github/gemsnote/mobile-app`，分支 develop。
- 最近提交：`f524502` 缓存偏好持久化与本进度索引；`bb48e43` 附件系统打开；`67431bb` HTML 链接确认操作；`505d83c` Markdown 网页链接。
- 本轮起始未提交改动全部属于上一轮缓存偏好持久化：schema v8、repository、workspace、测试和 docs；没有把它们覆盖。
- 缓存偏好：静态检查无问题，完整测试 463 项通过（上一轮日志 `/private/tmp/gemsnote-cache-pref-full.log`）；本轮已核对实际差异，提交前继续核验。
- 本轮 Android 构建实际失败：Gradle 9.3.1 all.zip 损坏，`zip END header not found`。日志 `/private/tmp/gemsnote-goal-build.log`，当前缓存文件 55,145,614 字节。尚未成功生成 APK，也没有原生设备验收证据。
- 当前任务：API2 JSON/表单禁止重定向已实现，核心合同 59 项、全量 478 项测试通过；修复构建环境中，官方 Gradle 完整包正在下载，尚未替换旧缓存。下一步继续离线笔记本/资源与双平台分享。

## 功能对照索引

路径以项目根目录为基准；表中 Flutter 路径省略 `mobile-app/`，旧版路径省略 `mobile-app/legacy-android/app/src/main/java/com/github/gemsnote/`。服务端路径中的 `api/` 是控制器目录名，不表示使用 Legacy URL；实际路由以 `conf/routes` 的 `/api2/...` 为准。

状态“部分”表示仍需实现或更强验证；现有测试名称是证据入口，不能代替真机结果。

| 编号 / 功能 | Desktop 对应 | 服务端 API2 对应 | 旧 Android 对应 | Flutter 现状 / API2 | 剩余工作与验收条件 |
|---|---|---|---|---|---|
| M01 登录、退出、离线登录 | desktop-app/api/client_api.go Auth/Logout | Api2Controller.TokenLogin；api/ApiAuthController | ui/SignInActivity、service/AccountService | lib/repositories/auth_repository.dart、data/session；API2 | 核心已实现；test/data/login_flow_test.dart、cached_login_test.dart；会话过期/离线真机验证 |
| M02 版本、USN、分页同步 | desktop-app/api/version.go、sync/pull.go、push.go | api/ApiUserController、ApiNoteController、ApiNotebookController、ApiTagController | background/NoteSyncService | lib/sync/sync_coordinator.dart；API2 | 部分；USN 回退、删除冲突及资源冲突尚未完整处理；全量/增量/并发修改必须不丢失数据 |
| M03 笔记离线增改、自动保存 | desktop-app/db/note_repo.go、sync/push.go | /api2/client/note/add、update | ui/edit/NoteEditActivity | data/database/app_database.dart、ui/note_editor_page.dart；API2 | 核心已实现；本地保存/后台切换测试已覆盖，输入法与杀进程验收待做 |
| M04 Markdown 工具及阅读 | desktop-app/webapi/local.go、共享前端编辑器 | ApiNoteController 正文 | ui/edit/EditorFragment | ui/markdown_editing.dart、markdown_note_body.dart；同步 API2 | 部分；复杂语法与旧编辑器工具逐项对照；markdown_tools_test.dart 等，原文不得被预览改写 |
| M05 富文本与表格 | desktop-app/webapi/local.go、共享前端编辑器 | ApiNoteController 正文 | ui/edit/EditorFragment | ui/visual_html_editor.dart、safe_html_note_body.dart；同步 API2 | 部分；复杂格式、合并单元格、可视化资源插入未完；WebView 输入法/选区/撤销真机验证 |
| M06 笔记本树及离线操作 | desktop-app/db/notebook_repo.go、api/client_api.go | /api2/client/notebook/add、update | service/NotebookService | ui/notebook_dialog.dart、move_notebook_dialog.dart；API2 | 联网增改移动已实现；离线队列未做，需临时 ID/依赖笔记/失败恢复验证 |
| M07 笔记本删除 | desktop-app/api/client_api.go DeleteNotebook | api/ApiNotebookController.DeleteNotebook → service/NotebookService.DeleteNotebookForce | service/NotebookService | 暂未接入 | 服务端合同阻塞：子级/笔记处理及 USN 删除标记；仅提出需求 |
| M08 移动、星标、回收站 | desktop-app/db/note_repo.go、sync/push.go | ApiNoteController.UpdateNote/DeleteTrash | service/NoteService | ui/note_reader_page.dart、workspace_page.dart；API2 | 核心已实现；trash_delete_test.dart、pending_sync_test.dart；跨客户端回收站回归待验证 |
| M09 完整复制与冲突副本 | desktop-app/webapi/local.go、sync/push.go | NoteController.CopyNote、ApiNoteController | service/NoteService | domain/models/conflict_copy.dart；API2 | 仅无资源保守子集；附件/图片克隆、复杂 HTML、删除冲突未完；不得丢资源或覆盖原笔记 |
| M10 搜索、排序、所有笔记 | desktop-app/db/note_repo.go | 本地搜索，内容来自 API2 同步 | ui/SearchActivity | ui/note_search_page.dart、domain/models/note_sort.dart | 本地实现；搜索分页、排序持久化已有测试；大数据量性能/FTS 待评估 |
| M11 标签编辑与管理 | desktop-app/api/client_api.go AddTag/DeleteTag | api/ApiTagController、ApiNoteController.UpdateNote | service/TagService | ui/tags_page.dart、note_tags_dialog.dart；API2 | 部分；全局管理待做，清空标签合同阻塞；删除所有标签后同步不能残留或产生空标签 |
| M12 历史浏览恢复 | desktop-app/api/client_api.go GetHistories/GetHistoryContent | ApiNoteController.GetHistories/GetHistoryContent | service/NoteService | ui/note_history_page.dart；API2 | 文本已实现；历史资源占位，媒体恢复语义待补；history_restore_test.dart |
| M13 共享笔记 | desktop-app/sharedsync/sharedsync.go、api/shared_api.go | api/ApiSharedController | 旧版无完整等价 | ui/shared_notes_page.dart、data/database shared cache；API2 | 只读列表/正文已实现；共享资源缓存与权限撤销、共享编辑和权限管理仍待核对/实现 |
| M14 图片缓存、预览、保存 | desktop-app/service/file_service.go | api/ApiFileController.GetImage | ui/PictureViewerActivity、service/NoteFileService | ui/cached_markdown_image.dart、services/image_exporter.dart；API2 | 已有缓存隔离/原始字节保存测试；原生文件窗口待验收 |
| M15 图片上传与正文插入 | desktop-app/webapi/proxy.go | /api2/file/pasteImage → File.PasteImage | ui/edit/NoteEditActivity | services/note_image_picker.dart、ui/note_image_upload_dialog.dart；API2 | 在线原文插入已实现；离线上传、WebView 插入和中断恢复未完 |
| M16 附件上传下载、打开、分享 | desktop-app/service/file_service.go、webapi/proxy.go | Api2.UploadAttachment、ApiFile.GetAttach | service/NoteFileService | ui/note_files_page.dart、services/attachment_*；API2 | 在线上传、下载、离线保存/分享/打开已实现；离线上传队列、原生 intent/DocumentInteraction 验证未完 |
| M17 资源任务与缓存管理 | desktop-app/service/file_service.go | ApiNote.GetNote + ApiFile | background/NoteSyncService | services/account_file_cache.dart、file_cache_batch.dart、ui/file_cache_dialog.dart；API2 | 进程内任务/清理/64MiB 配额已实现；持久队列、失败恢复和系统后台执行未完 |
| M18 缓存偏好持久化 | desktop-app/db 配置、service/file_service.go | 无新增请求 | ui/SettingsActivity | app_database schema v8、workspace_page；本地 | 已提交 f524502；账号隔离、升级、读写失败/重试测试通过 |
| M19 账号资料、头像、密码 | desktop-app/webapi/background_profile.go、proxy.go | Api2.UploadAvatar、User.UpdateUsername/UpdatePwd、web/emailChange | ui/SettingsActivity | ui/account_page.dart、avatar_upload_dialog.dart；API2 + 允许的公开头像 | 主要功能已实现；头像相机/裁剪/更多格式未完；帐号变更与缓存竞态验收 |
| M20 默认编辑器、语言、关于 | desktop-app/webapi/about.go、应用配置 | 默认编辑器与语言本地；协议版本 API2 | ui/SettingsActivity、AboutActivity | default_editor_dialog.dart、about_dialog.dart；API2 | 编辑器/版本已实现，界面国际化与语言设置未实现；中英系统及切换测试待做 |
| M21 多账号快速切换 | desktop-app/app.go、db 配置 | Api2.TokenLogin、ApiUser.Info | service/AccountService、ui/MainActivity | app.dart、data/session/session_store.dart | 未完成；当前单活动 session；账号切换不能串缓存/资源/待处理分享 |
| M22 导入导出、对外分享 | desktop-app/webapi/local.go | 本地操作无需新接口 | ui/edit/NoteEditActivity | services/note_importer.dart、note_exporter.dart、note_sharer.dart | 原文导入导出及系统分享已实现；完整含资源导出仍待对照；Android/iOS 文件与分享面板验收 |
| M23 Android/iOS 分享接收 | Desktop 无平台等价 | 本地导入后 API2 笔记上传 | manifest ACTION_SEND、ui/edit/NoteEditActivity | services/shared_text_inbox.dart、Android MainActivity | Android 纯文本已实现；Android 文件/图片/多项及 iOS Share Extension 未实现；冷/热启动、队列持久化/账号确认/幂等测试 |
| M24 Android 小组件 | Desktop 无等价 | 本地快照，无新接口 | appwidget/NoteAppWidget、WidgetService、RedirActivity | 未实现 | 笔记列表/新建入口、账号切换、锁屏隐私、刷新及系统生命周期验收 |
| M25 Android/iOS 发布与运行 | desktop-app/.github/workflows 为发布参考 | 无 | 旧 Android 构建参考 | android、ios、.github/workflows | Android 构建当前被损坏 Gradle 包阻塞；iOS 模拟器/签名/设备验收未完成；不自动发布 |
| M26 API2 边界与网络错误 | desktop-app/api/client.go | conf/routes、Api2Controller、api/* | 禁止复用旧请求 | lib/core/api/api2_client.dart | 未发现直接 Legacy 业务调用；JSON/表单已禁止自动重定向，真实 HTTP 测试覆盖 GET/JSON/form × 301/302/303/307/308；旧正文路径仅解析 FileId，绝不请求原路径 |

## API2 审计与接口缺口

已检查 Flutter HTTP 调用集中在 `lib/core/api/api2_client.dart`，业务字面路径均为 `/api2/`。
`domain/models/note_image_reference.dart` 识别旧 `/api/file/getImage` 只用于提取 ID 并读本地缓存，不能因此删除历史正文兼容，也不能据此宣称存在旧 API 调用。
公开头像下载是用户明确允许的例外，不是业务 API 回退。

- B01：笔记本删除：`ApiNotebook.DeleteNotebook` 调用 `DeleteNotebookForce`。需要明确非空笔记本处理、树结构一致性、幂等和 USN tombstone，跨端增量同步后必须一致。
- B02：清空标签：`ApiNoteController.UpdateNote` 仅在 `Has("Tags[0]")` 时更新；需要明确表达空集合且不会创建空标签的合同，以及向后兼容策略。
- B03：共享编辑/权限管理：需继续核对 desktop 代理与服务端权限合同，不能把 readonly shared snapshot 当作写权限。
- B04：上传依赖 API2 浏览器 session；已实现一次性会话登录/身份校验/注销，未回退 Legacy。离线队列需要明确凭据获取与重试幂等。

以上服务端需求只记录，不修改服务端。

## 恢复与验收规则

每轮先读本文件与 `git -C mobile-app status --short`，核对当前源码。每项独立功能审查 diff、静态检查、相关测试，定期全量测试和 Android 构建；失败如实记录并修复。不得将未验证的平台行为记为完成。
提交前明确暂存路径并检查 cached diff。提交 hash 在下一次功能更新时记入本文件，避免为写自身 hash 反复追加提交。
当前整体目标未完成：表中所有“部分/未实现/阻塞/待验证”保持可追踪，不因某个单元通过而缩小目标。

## 本轮验证补充

M26：`test/core/api2_redirect_test.dart` 使用本地真实 HTTP server + IOClient，
返回重定向到 `/api/legacy-target`，确认只收到一次原 API2 请求并返回 ApiException。
已有 JSON/表单字段、认证和上传测试保持通过。未改变公开头像允许策略，
没有修改服务端或 desktop 的默认重定向行为。
全量测试日志 `/private/tmp/gemsnote-api2-full.log`：478 passed。
