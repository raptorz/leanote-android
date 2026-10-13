# Flutter 持续迁移进度

本文件为长期目标的恢复入口。详细历史实现说明保留在 [docs/MIGRATION.md](docs/MIGRATION.md)，开发细节见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。不能把历史勾选项等同于整体验收。

## 约束及范围

- 主工作目录保持服务端仓库根目录。所有 Git 操作明确使用 `git -C mobile-app`；只提交此独立仓库的相关文件，不 push、不改写历史。
- 服务端、desktop-app、legacy-android 仅作只读参考，不修改。主 Agent 顺序执行。
- 业务通信必须为 API2。用户已明确允许公开头像直接访问；沿用同源、不携带凭据、不跟随重定向的下载策略。
- 2026-10-13 最新范围：iOS 原生实现与验证暂缓，发布工作暂缓；继续完成其余功能迁移。已有 iOS 代码保留，共享 Flutter 功能仍继续实现。
- 服务端修改不属于本次目标。确认缺口后记录具体需求，交由后续处理，不回退 Legacy API。
- 旧 Android 小组件保留为目标。深链、生物识别属于既有规划扩展，是否为旧功能对应项还需核对，不能冒充已迁移。
- 注册、博客、演示账号、旧数据库迁移目前按原迁移方案排除；若发现与必要移动功能有依赖需重新记录。

## 当前现场（2026-10-13）

- 独立仓库已确认：`/Users/raptor/Documents/github/gemsnote/mobile-app`，分支 develop。
- 最近提交：`1a6893b` Android 文本文件和多项分享；`1ee2d61` 标签目录与 API2 在线创建；`536de61` iOS 分享标题字节限制；`fddcb90` iOS 文本/网页分享扩展；`035ac4c` 已有笔记本离线重命名/移动；`5700811` 多账号离线切换；`515455e` API2 禁止自动重定向；`f524502` 缓存偏好持久化与本进度索引；`bb48e43` 附件系统打开；`67431bb` HTML 链接确认操作；`505d83c` Markdown 网页链接。
- 2026-10-13 恢复时工作区干净。最新静态检查无问题，完整 Flutter 测试 526 项通过，Android debug APK 构建通过。旧批次验证记录保留在后文，不能当成最新运行结果。
- Android 构建已恢复：曾因 Gradle 9.3.1 all.zip 损坏失败，已通过官方 SHA-256 验证并替换，补齐 NDK/SDK/CMake 后首次及增量 debug APK 构建成功。尚无真机验收证据。
- 当前任务：M17 下载队列已持久化并验证，接着补齐离线上传与 Android 资源类分享。iOS 与发布按最新要求暂缓，不作为当前功能迁移的执行前置条件。

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
| M06 笔记本树及离线操作 | desktop-app/db/notebook_repo.go、api/client_api.go | /api2/client/notebook/add、update | service/NotebookService | ui/notebook_dialog.dart、move_notebook_dialog.dart；API2 | 在线新建已实现；已有笔记本重命名/移动已改为离线保存、API2 同步队列（schema v9）；离线新建/不确定结果恢复、完整冲突处理仍未完 |
| M07 笔记本删除 | desktop-app/api/client_api.go DeleteNotebook | api/ApiNotebookController.DeleteNotebook → service/NotebookService.DeleteNotebookForce | service/NotebookService | 暂未接入 | 服务端合同阻塞：子级/笔记处理及 USN 删除标记；仅提出需求 |
| M08 移动、星标、回收站 | desktop-app/db/note_repo.go、sync/push.go | ApiNoteController.UpdateNote/DeleteTrash | service/NoteService | ui/note_reader_page.dart、workspace_page.dart；API2 | 核心已实现；trash_delete_test.dart、pending_sync_test.dart；跨客户端回收站回归待验证 |
| M09 完整复制与冲突副本 | desktop-app/webapi/local.go、sync/push.go | NoteController.CopyNote、ApiNoteController | service/NoteService | domain/models/conflict_copy.dart；API2 | 仅无资源保守子集；附件/图片克隆、复杂 HTML、删除冲突未完；不得丢资源或覆盖原笔记 |
| M10 搜索、排序、所有笔记 | desktop-app/db/note_repo.go | 本地搜索，内容来自 API2 同步 | ui/SearchActivity | ui/note_search_page.dart、domain/models/note_sort.dart | 本地实现；搜索分页、排序持久化已有测试；大数据量性能/FTS 待评估 |
| M11 标签编辑与管理 | desktop-app/api/client_api.go AddTag/DeleteTag | api/ApiTagController、ApiNoteController.UpdateNote | service/TagService | ui/tags_page.dart、note_tags_dialog.dart；API2 | 部分；新增未使用标签目录、在线创建及笔记编辑候选；全局删除/重命名未完成，删除 USN 合同 B06 与清空标签 B02 待服务端后续处理 |
| M12 历史浏览恢复 | desktop-app/api/client_api.go GetHistories/GetHistoryContent | ApiNoteController.GetHistories/GetHistoryContent | service/NoteService | ui/note_history_page.dart；API2 | 文本已实现；历史资源占位，媒体恢复语义待补；history_restore_test.dart |
| M13 共享笔记 | desktop-app/sharedsync/sharedsync.go、api/shared_api.go | api/ApiSharedController | 旧版无完整等价 | ui/shared_notes_page.dart、data/database shared cache；API2 | 只读列表/正文已实现；共享资源缓存与权限撤销、共享编辑和权限管理仍待核对/实现 |
| M14 图片缓存、预览、保存 | desktop-app/service/file_service.go | api/ApiFileController.GetImage | ui/PictureViewerActivity、service/NoteFileService | ui/cached_markdown_image.dart、services/image_exporter.dart；API2 | 已有缓存隔离/原始字节保存测试；原生文件窗口待验收 |
| M15 图片上传与正文插入 | desktop-app/webapi/proxy.go | /api2/file/pasteImage → File.PasteImage | ui/edit/NoteEditActivity | services/note_image_picker.dart、ui/note_image_upload_dialog.dart；API2 | 在线原文插入已实现；离线上传、WebView 插入和中断恢复未完 |
| M16 附件上传下载、打开、分享 | desktop-app/service/file_service.go、webapi/proxy.go | Api2.UploadAttachment、ApiFile.GetAttach | service/NoteFileService | ui/note_files_page.dart、services/attachment_*；API2 | 在线上传、下载、离线保存/分享/打开已实现；离线上传队列、原生 intent/DocumentInteraction 验证未完 |
| M17 资源任务与缓存管理 | desktop-app/service/file_service.go | ApiNote.GetNote + ApiFile | background/NoteSyncService | services/account_file_cache.dart、file_cache_batch.dart、ui/file_cache_dialog.dart；API2 | 账号资源下载队列已持久化（schema v10），支持重启/暂停续传、逐文件失败恢复、失效快照拦截；64MiB 缓存与任务清理已实现；离线上传与系统后台执行未完 |
| M18 缓存偏好持久化 | desktop-app/db 配置、service/file_service.go | 无新增请求 | ui/SettingsActivity | app_database schema v8、workspace_page；本地 | 已提交 f524502；账号隔离、升级、读写失败/重试测试通过 |
| M19 账号资料、头像、密码 | desktop-app/webapi/background_profile.go、proxy.go | Api2.UploadAvatar、User.UpdateUsername/UpdatePwd、web/emailChange | ui/SettingsActivity | ui/account_page.dart、avatar_upload_dialog.dart；API2 + 允许的公开头像 | 主要功能已实现；头像相机/裁剪/更多格式未完；帐号变更与缓存竞态验收 |
| M20 默认编辑器、语言、关于 | desktop-app/webapi/about.go、应用配置 | 默认编辑器与语言本地；协议版本 API2 | ui/SettingsActivity、AboutActivity | default_editor_dialog.dart、about_dialog.dart；API2 | 编辑器/版本已实现，界面国际化与语言设置未实现；中英系统及切换测试待做 |
| M21 多账号快速切换 | desktop-app/app.go、db 配置 | Api2.TokenLogin、ApiUser.Info | service/AccountService、ui/MainActivity | app.dart、data/session/session_store.dart | 本轮实现切换/添加账号、登录页恢复已登录账号；保留离线修改与多账号凭据，切换前等待资源任务、重建工作区；静态检查和全量 488 项测试通过；原生安全存储/生命周期验收仍待进行 |
| M22 导入导出、对外分享 | desktop-app/webapi/local.go | 本地操作无需新接口 | ui/edit/NoteEditActivity | services/note_importer.dart、note_exporter.dart、note_sharer.dart | 原文导入导出及系统分享已实现；完整含资源导出仍待对照；Android/iOS 文件与分享面板验收 |
| M23 Android/iOS 分享接收 | Desktop 无平台等价 | 本地导入后 API2 笔记上传 | manifest ACTION_SEND、ui/edit/NoteEditActivity | services/shared_text_inbox.dart、Android MainActivity、ios/ShareExtension 与 Shared | Android 单项/多项文本及文本文件已实现，JVM/Flutter 测试和 APK 构建通过；iOS 单项文本/网页与 App Group 队列已有，存储测试通过但 iOS 构建/签名/真机待验收；二进制资源、iOS 文件/多项未完成 |
| M24 Android 小组件 | Desktop 无等价 | 本地快照，无新接口 | appwidget/NoteAppWidget、WidgetService、RedirActivity | 未实现 | 笔记列表/新建入口、账号切换、锁屏隐私、刷新及系统生命周期验收 |
| M25 Android/iOS 发布与运行 | desktop-app/.github/workflows 为发布参考 | 无 | 旧 Android 构建参考 | android、ios、.github/workflows | 损坏 Gradle 包已修复，Android debug APK 已构建成功；iOS 模拟器/签名/设备验收未完成；不自动发布 |
| M26 API2 边界与网络错误 | desktop-app/api/client.go | conf/routes、Api2Controller、api/* | 禁止复用旧请求 | lib/core/api/api2_client.dart | 未发现直接 Legacy 业务调用；JSON/表单已禁止自动重定向，真实 HTTP 测试覆盖 GET/JSON/form × 301/302/303/307/308；旧正文路径仅解析 FileId，绝不请求原路径 |

## API2 审计与接口缺口

已检查 Flutter HTTP 调用集中在 `lib/core/api/api2_client.dart`，业务字面路径均为 `/api2/`。
`domain/models/note_image_reference.dart` 识别旧 `/api/file/getImage` 只用于提取 ID 并读本地缓存，不能因此删除历史正文兼容，也不能据此宣称存在旧 API 调用。
公开头像下载是用户明确允许的例外，不是业务 API 回退。

- B01：笔记本删除：`ApiNotebook.DeleteNotebook` 调用 `DeleteNotebookForce`。需要明确非空笔记本处理、树结构一致性、幂等和 USN tombstone，跨端增量同步后必须一致。
- B02：清空标签：`ApiNoteController.UpdateNote` 仅在 `Has("Tags[0]")` 时更新；需要明确表达空集合且不会创建空标签的合同，以及向后兼容策略。
- B03：共享编辑/权限管理：需继续核对 desktop 代理与服务端权限合同，不能把 readonly shared snapshot 当作写权限。
- B04：上传依赖 API2 浏览器 session；已实现一次性会话登录/身份校验/注销，未回退 Legacy。离线队列需要明确凭据获取与重试幂等。

- B06：`TagService.DeleteTagApi` 返回递增的 `toUsn`，却向数据库写入传入的旧 `usn`；`GeSyncTags` 使用 `Usn > afterUsn`，已同步客户端可能永远收不到删除。该 API 也不调用 `UpdateNoteToDeleteTag`，与旧 Web 全局删除行为不同。后续需明确是目录隐藏还是从所有笔记移除，并修正递增 USN、并发条件更新和删除重放；客户端暂不接入全局删除，也不能以删除重建冒充重命名。

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

## 构建恢复记录

官方完整 Gradle 9.3.1 all.zip 已下载，并核验官方 SHA-256：
`17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43`；ZIP 全部条目 CRC 检查通过。
已将损坏缓存备份至 `/private/tmp/gemsnote-gradle-corrupt-backup.zip`，并以同版本正确包替换。
未更改仓库 Gradle 版本或删除其他缓存。
重新执行 `flutter build apk --debug --no-pub`，进程工具 session **32002** 已成功退出（后续进展）；
首次成功日志 `/private/tmp/gemsnote-first-successful-build.log`，当时 Gradle daemon PID 40720。
该 session 已结束；后续增量构建日志为 `/private/tmp/gemsnote-goal-build-repaired.log`。
M26 改动静态分析最终无问题；全量 478 测试通过。整个迁移目标仍未完成。

## 下一项接口核对：M06 离线笔记本

已对照 `desktop-app/sync/push.go::sendNotebookChanges`：父节点优先，上传成功后替换关联 ID。
服务端 `ApiNotebookController.AddNotebook` 每次生成新的 ObjectId，没有 ClientNotebookId 或幂等键；
网络中断后自动重发创建会产生重复笔记本。因此不能直接照搬重复重试。
B05（后续服务端需求）：增加创建幂等标识或查询创建结果能力，并遵循 API2 兼容规则。
客户端仍可实现离线队列/编辑/依赖映射及不确定状态的明确恢复流程，不能以此阻塞全部迁移。
更新/移动使用源 USN，待验证重放、远端冲突与本地并发编辑；父级链校验仍由客户端快照承担。
后续实现时必须涵盖 SQLite 快照合并、重置/退出保护和 dirty 指示，不能只加 UI 开关。

## M21 多账号切换实现（本轮）

- 参考 `desktop-app/app.go::SwitchUser`、`desktop-app/db/file_repo.go::SwitchUser` 及旧版 AccountService/SettingsActivity。移动端保持 API2 登录，不复用旧密码存储或旧 API。
- 账号菜单新增切换/添加入口，显示服务器与用户标识。只列出仍有安全存储凭据的账号；已退出账号保留数据库但需重新登录。
- 切换在本地事务中更新唯一活动账号；保留其他账号 token、dirty 笔记、同步游标、设置和资源缓存，不自动同步。登录页也可直接选择其他已登录账号，恢复时不触发头像联网刷新。
- 切换页先停止并等待旧账号资源任务，等待时阻止返回和重复操作；同步/上传中禁止切换。成功后按账号与会话代次重建工作区，清空旧页面选择与计时器。
- 添加账号复用既有 API2 登录/缓存确认；等待登录时禁止返回，取消不改变账号。新快照成功但安全存储失败时恢复原活动账号，保留原离线修改。
- 分享通道改为按 messenger/channel 追踪当前 owner，旧工作区晚销毁不会清空新 handler；待处理分享账号绑定规则保持。
- `test/data/account_switch_test.dart` 覆盖服务器/用户隔离、dirty/游标/偏好保留、恢复、凭据丢失、上传互斥、新登录失败回滚。
- `test/account_switcher_page_test.dart` 覆盖工作区重建、资源任务等待、读写失败/重试、返回保护、取消添加及登录页恢复。
- `test/shared_text_inbox_test.dart` 验证旧实例销毁后的新平台消息仍可接收。
- 当时 Android 构建 session 32002 尚运行（现已成功退出）；已完成 NDK 28.2.13676358 下载及安装。线程栈证实此前在 SDK LegacyDownloader 等待网络，并非源码编译失败。原生多账号/分享冷启动验收仍待设备。

M21 最终验证：`flutter analyze --no-pub` 无问题；`flutter test --no-pub` **488 项全部通过**，
日志 `/private/tmp/gemsnote-multiaccount-full.log`。测试过程中修正了一个未切换到登出态的测试夹具，
最终全量重新通过，没有删除失败测试或缩减断言。
构建 session 32002 随后完成 Android SDK Platform 36/34 安装，并已成功退出。
下一优先项继续 M06 离线笔记本操作及 M23 双平台分享接收；服务端幂等/删除/标签缺口维持只读记录。

M21 已提交 `5700811`。本机构建实际生成 `android/.kotlin/sessions/*.salive`，
已加入精确忽略规则 `/android/.kotlin/`，不跟踪编译器缓存，也没有删除缓存。

## M06 已有笔记本离线重命名与移动

- 对照 Desktop notebook dirty 队列与父节点优先上传，服务端 `ApiNotebook.UpdateNotebook` / `NotebookService.UpdateNotebookApi`：携带源 USN，成功递增 USN；冲突不覆盖。
- schema v9 为 notebooks 增加 is_dirty；重命名只修改 title，移动只修改 parent，事务内检查当前层级/非法目标，保存无需网络。新建仍需联网（B05 不变）。
- 同步先上传待修改笔记本，再上传笔记；按最终父级链排序，父节点先于子节点，避免父子关系反转的临时循环。循环/缺失父级保留待同步状态并报错。
- 响应只确认提交快照，等待期间的新编辑保留 dirty 并更新基础 USN；不会改全局下载游标。上传回包校验 ID/标题/父级/序号/USN。
- 上次回包丢失时，下次发生 conflict 会通过 API2 增量笔记本列表核对：仅目标字段完全相同时确认成功；真实冲突保留本地修改并提示，不猜测覆盖。
- 普通下载合并/在线回包不能覆盖 dirty 笔记本。重新同步沿用确认流程，其快照指纹扩展至笔记和笔记本，拒绝下载期间产生的新修改。
- 退出前尝试上传笔记与笔记本，失败需使用既有明确保留本地修改的退出选项；待同步笔记本显示圆点，同步按钮统计包括笔记本。
- UI 的已有笔记本重命名和移动默认进入本地队列；保留新建联网入口。界面明确说明保存本机后下次同步上传。
- 测试：`test/data/offline_notebook_test.dart` 覆盖重启/升级、非法层级、无变化、账号隔离、迟到回包、失败回滚、重置与退出、丢失回包核对及父子反转上传顺序；`test/offline_notebook_dialog_test.dart` 验证界面实际走离线路径与待同步指示。
- 本项不是整个 M06 完成：离线新建、选择性冲突解决界面、删除和跨客户端完整父级链校验仍待实现或服务端支持。真实冲突不自动丢弃；可先核对服务端，必要时明确确认重新同步，后者会丢弃该账号待上传修改。

## Android 构建验证更新

原 session 32002 已成功生成 APK（首次构建 3995.5 秒，含下载 NDK、Android 36/34、CMake）。
源码收敛后增量构建也通过（8.3 秒），没有修改仓库 Gradle/AGP 版本。
产物 `build/app/outputs/flutter-apk/app-debug.apk`（约 162 MiB，debug，未提交）。
`aapt dump permissions` 确认只有 INTERNET 以及应用自身 DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION，
没有 READ_EXTERNAL_STORAGE 或 READ_MEDIA_*。这证明 APK 合并结果，不等于外部应用打开/分享真机已验证。
原生安装运行、iOS 签名与分享扩展仍待后续完成。

M06 本批最终验证：静态检查无问题；完整测试 **501 项全部通过**
（`/private/tmp/gemsnote-offline-book-full.log`）。最终原子快照读取改动后的 Android debug
增量构建通过（11.5 秒，session 62456 已退出 0），APK 权限复查符合预期。
本轮无构建进程需要继续等待。下一轮直接从 Git/本文件恢复并推进 M23 双平台分享接收。

## M23 iOS 文本与网页分享接收（2026-10-13）

- 新增 ShareExtension target，Runner 在 Thin Binary 之前嵌入扩展，并建立构建依赖；三种配置共用 App Group entitlement，版本跟随 Flutter。
- 扩展接收单项纯文本或 HTTP(S) URL，可编辑后保存；拒绝不支持的输入/多项，不访问链接，不在扩展登录。主应用前台刷新后沿用现有账号/笔记本确认、claim、稳定 ID 幂等导入和成功后 acknowledge。
- App Group 队列独立于 Flutter 生命周期，最多 8 项、单项 256 KiB UTF-8；跨进程 flock + 原子写入，保留损坏数据并报错，不共享凭据。取消、重复提交、异步读取超时和写入失败均有保护。
- Swift 生产存储源码在本机 CLT 编译并执行测试，持久化/账号绑定/容量/字节限制/损坏文件/8 进程并发全部通过；脚本 `scripts/test_ios_share_store.sh`。
- plist/pbxproj 解析、工程引用、依赖/嵌入顺序、全部配置 entitlement 校验通过；Swift 界面与桥接源码语法解析通过（不是 UIKit 类型检查）。
- Flutter analyze 无问题，完整测试 **503 项通过**；日志沿用 `/private/tmp/gemsnote-offline-book-analyze.log` 与 `/private/tmp/gemsnote-offline-book-full.log`，已覆盖旧日志。
- 本机只有 `/Library/Developer/CommandLineTools`，无完整 Xcode。扩展编译、App Group provisioning、模拟器/设备/归档均未宣称完成；详见 `docs/IOS_SHARING.md`。
- 整体 M23 未完成：双平台文件/图片/多项、原生输入提供方兼容与生命周期验收待做。没有改服务端或新增 Legacy 请求。
- 恢复执行时发现 Goal 元数据为 blocked；当前仍存在独立可执行工作，不能据此停止全部迁移，也不能把本次文本子集标成整个目标完成。
- 本批 Android debug APK 回归构建通过（12.5 秒，session 32680 已退出 0），日志 `/private/tmp/gemsnote-goal-build-repaired.log`；这是 Android 构建证据，不是 iOS 扩展验证。

## M11 标签目录及在线创建（2026-10-13）

- 对照 Desktop `api/client_api.go::AddTag` 与服务端 `ApiTag.AddTag` / `TagService.AddOrUpdateTag`，新增 API2 `POST /api2/tag/addTag` 表单调用，校验回包名称、账号、正 USN 和非删除状态；禁止重定向。
- 标签页默认仍按本地笔记引用数显示前 10；可显示全部目录标签（包含零引用项）并过滤。数量来自本地未删除且非回收站笔记，不采信服务端可能过期的 Count。
- 在线创建不修改已有笔记；服务端确认后缓存到当前账号目录，不推进同步游标。重复名称复用服务端已有记录语义，失败不自动重发；回包不确定时提示先同步核对。
- 笔记标签编辑候选包含未使用标签；选择后仍走本地笔记 dirty 队列与 API2 同步。原有“使用中的标签”浏览统计不变。
- 创建与同步、上传、全量快照及账号切换互斥，创建中禁止退出；界面防重复提交，失败保留输入并可重试。
- 新增 `test/data/tag_catalog_test.dart` 和 `test/tag_catalog_page_test.dart`：API2 表单/编码、账号隔离、非法响应、离线失败、dirty/游标保留、互斥、列表过滤、零引用候选、失败重试与返回保护。
- 静态分析无问题，完整 **515 项测试通过**；Android debug APK 构建通过（10.0 秒，session 51994 已退出 0）。最新日志仍为 `/private/tmp/gemsnote-offline-book-analyze.log`、`/private/tmp/gemsnote-offline-book-full.log`、`/private/tmp/gemsnote-goal-build-repaired.log`。
- M11 尚未全部完成：全局删除/重命名缺少可靠合同，已记录 B06；清空笔记标签仍受 B02 限制；本次未改服务端。
- iOS 分享子集已提交 `fddcb90`；标题字节上限与组合字符测试后续提交 `536de61`，原生存储测试再次通过；iOS 设备验证状态未变化。

## M23 Android 文本文件及多项分享（2026-10-13）

- M11 已提交 `1ee2d61`，继续执行本项；未修改服务端、Desktop 或 legacy-android。
- 参考旧 `NoteEditActivity.getNoteFromShareIntent` 的本地草稿行为，以及 Android 官方 SEND/SEND_MULTIPLE / EXTRA_STREAM 合同；复用已实现的账号确认、稳定分享 ID 和本地 dirty 笔记/API2 同步。
- Manifest 增加 SEND_MULTIPLE 与 text/markdown，仅声明能读取的文本 MIME；接收单项/多项纯文本和 content URI 文本文件。严格 UTF-8/BOM 解码，拒绝 NUL/空白、非法编码和超出 256 KiB 的单项内容。
- 每批最多 8 项，文本文件附带的说明文本另作收件项保留。后台最多 2 个 worker，15 秒超时拒绝迟到结果；全部准备成功后读取最新队列并一次保存，不因中间一项失败留下半批新增内容。
- 只读取系统允许的 content URI，拒绝自身 provider；不索取媒体/存储权限，不持久保留来源 URI 权限。成功前进程终止的未完成读取需重新分享，不虚报已持久保存。
- 新增 JVM 生产解码器回归脚本 `scripts/test_android_share_decoder.sh`，通过 UTF-8/BOM/跨块、字节边界、无限长度流上界、读取失败、中断及 Unicode 标题测试。
- Flutter 新测试验证处理首项后显现次项且不自动绑定其账号；完整 **516 项通过**，静态检查无问题。Android 最终 debug APK 构建通过（3.2 秒，session 62529 已退出 0）。
- aapt 复核合并 Manifest 确认 SEND/SEND_MULTIPLE 和 text/plain、text/markdown；权限仍仅 INTERNET 和应用自身 receiver permission，没有存储/媒体读取权限。
- 另对齐 iOS 与 Dart 的 BOM/Unicode 空白验证，避免仅含不可见空白的记录入队后无法由 Flutter 读取；Swift 生产存储测试再次全部通过。
- 当前未有设备运行证据；URI 授权、跨应用/云端 provider、冷热启动和超时生命周期见 `docs/ANDROID_SHARING.md`。Android 图片/二进制附件接收、iOS 文件/多项分享仍待迁移，整个目标未完成。

## M17：持久资源下载队列（2026-10-13）

- schema v10 保存账号、笔记 USN、逐文件缓存代次与结果；重启或暂停后只续传未完成项。并发仍限制为 3，停止等待已开始请求结束。
- 登录只读取任务状态，不自动联网；账号菜单手动开始或已开启的同步后缓存触发恢复。笔记版本/文件列表变化后旧任务失效，清理缓存同时删除下载任务；配额淘汰不会形成重复下载循环。
- 任务没有密码/token；账号隔离、会话切换仍等待下载排空。下载进度不修改同步游标或笔记正文。
- 新增 SQLite 重开进程模拟、失败/暂停续传、列表重试、字节写入后未确认、旧代次回调、账号隔离、配额淘汰和 v9 升级测试；界面恢复不联网及仅待办任务清理有回归覆盖。
- 静态检查通过，完整 Flutter 测试 526 项通过。本批未新增原生代码，Android 构建证据仍为上批；系统后台执行与设备验收没有完成。
