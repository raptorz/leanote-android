# Flutter 持续迁移进度

本文件为长期目标的恢复入口并保留逐批历史记录。面向读者的当前状态摘要见 [docs/MIGRATION.md](docs/MIGRATION.md)，开发细节见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。不能把历史勾选项等同于整体验收。

## 约束及范围

- 主工作目录保持服务端仓库根目录。所有 Git 操作明确使用 `git -C mobile-app`；只提交此独立仓库的相关文件，不 push、不改写历史。
- `legacy-android` 仅作只读参考。服务端和 desktop 的共享只读、同步合同修复已在用户明确授权后完成。
- 业务通信必须为 API2。用户已明确允许公开头像直接访问；沿用同源、不携带凭据、不跟随重定向的下载策略。
- 2026-10-21 最新范围：主体迁移完成；旧 Cookie 流程遗留的多余密码输入已清理，真实 API2/PostgreSQL 联调 7 项全部通过，账号绑定深链接与可选生物识别应用锁已经实现。完整 Flutter 791 项通过、9 项条件跳过，Android Debug APK 与 iOS 模拟器 Debug 构建通过。真机、发布签名和真实域名关联按用户要求暂缓。
- 服务端 B01/B02/B03/B06 已修复；B07 已补完整快照、附件原件保留和在线恢复接口；Flutter 继续只使用 API2，不回退 Legacy API。
- 旧 Android 小组件保留为目标。深链、生物识别属于既有规划扩展，是否为旧功能对应项还需核对，不能冒充已迁移。
- 注册、博客、演示账号、旧数据库迁移目前按原迁移方案排除；若发现与必要移动功能有依赖需重新记录。

## 下一阶段计划（2026-10-21）

1. 在全新 PostgreSQL 临时库重跑共享复制、历史连续写入/完整恢复、token 撤销、跨账号拒绝和响应丢失幂等场景。API2 token 不要求 JWT 格式，但服务端生成值必须密码学安全、不可预测且可撤销，客户端不得将其写入 URL或日志。
2. 实现 Android App Links/iOS Universal Links，限定受支持同源目标，覆盖未登录恢复导航、非法目标和跨账号拒绝。
3. 实现可选的本地生物识别应用锁，保留系统凭据回退；它只保护本机已保存会话，不代替服务端认证。

多余凭据输入已完成清理：用户名、头像、正文图片和附件上传不再要求账号或密码，API、repository 和上传对话框直接使用已保存 Bearer token；邮箱变更和密码修改保留必要密码确认。完整 Flutter **783 项通过、8 项条件跳过**，静态分析无问题。

真机验收中，WebView 输入法/选区、真实相机和第三方应用兼容性需要真机；WorkManager/BGProcessing 的长期唤醒、锁屏和系统回收必须以真机为最终证据。弱网、大数据量及 Web/Desktop/Mobile 并发可先用宿主和模拟器自动化，之后再做少量真机确认。Android/iOS 正式签名和发布继续暂缓。

## 当前现场（2026-10-21）

- 当前完成审计：完整 Flutter 回归 **787 项通过、8 项条件跳过（81 秒）**；跳过项为
  6 项显式临时 API2 联调、浏览器运行时专项和性能基准。静态分析无问题，Android/iOS
  普通应用构建及模拟器启动已有本页最新证据。网络调用复查只发现历史正文/归档中旧资源
  URL 的 ID 解析兼容，实际下载仍改写为 API2；没有 Legacy API 业务请求。当前范围内能由
  Flutter、Android/iOS 模拟器和本地自动化验证的功能已闭环；真机、发布及已记录的服务端
  JWT/共享复制/PostgreSQL 历史问题不计入本轮移动端功能迁移门槛。

- M16 iOS 附件原生打开专项 **1 项 UI 测试通过（20.8 秒）**：生产
  `AttachmentOpener` 通过 `open_filex` 的 DocumentInteraction/Quick Look，把二进制及
  空附件实际“拷贝到”独立 OpenReceiver 应用；接收应用读取文件后由测试核对安全文件名和
  原件字节。Flutter 模拟器入口构建通过，证据
  `/private/tmp/gemsnote-ios-attachment-open-final2.log` 和
  `/var/folders/6h/jjvzsttd0ms0j80_cfqgvt8c0000gn/T/gemsnote-open-ios.rDyR7K`。
  静态分析无问题；普通 iOS 模拟器应用重新构建通过（14.8 秒）、覆盖安装并启动成功，
  随后关闭模拟器。不代表其他文件类型、第三方应用、iPad 或真机兼容性；下一步继续
  工作区完整链路审计。

- M16 Android 附件原生打开专项 **1 项通过**：生产 `AttachmentOpener` 通过
  `open_filex` 和系统“打开方式”面板将二进制及空附件交给独立本地接收 Activity，
  宿主核对安全文件名、`application/octet-stream`、`content://` URI、临时读取授权和
  原件字节完全一致。测试不登录、不联网，也不代表其他文件类型、第三方应用或真机兼容性。
  证据 `/private/tmp/gemsnote-android-attachment-open-final.log` 和
  `/var/folders/6h/jjvzsttd0ms0j80_cfqgvt8c0000gn/T/gemsnote-attachment-open-1adoml57`。
  静态分析无问题，附件打开回归 **11 项通过**；普通 APK 构建通过（13.0 秒），覆盖安装及
  冷启动成功。iOS 对应验证见上文；服务端联合整改不变。

- iOS 对外分享收尾：普通 `lib/main.dart` 模拟器构建通过（59.2 秒），已覆盖安装并启动成功，随后正常关闭模拟器；独立 ReceiverHost 接收应用已卸载。日志 `/private/tmp/gemsnote-ios-outbound-restore.log`。本批没有生产源码变更，不重复上一批已通过的 787 项 Flutter 全套和 Android 构建。下一步继续附件外部打开和工作区完整流程；服务端 JWT/共享复制/历史更新仍按用户要求留待联合处理。

- 上批 `347ddc5` 完成 Android 对外分享。本批 M22/M16 iOS 使用生产 NoteSharer/AttachmentSharer、真实系统面板及独立 ShareReceiver 扩展，**1 项 UI 测试通过（43 秒）**：Markdown/HTML 标题与原文完整一致，二进制/空附件的文件名及原件逐字节一致；点击紧凑分享面板外的背景后，先验证面板消失，再验证调用返回。只使用合成数据，没有真实账号、服务器或外部服务发送。静态分析通过（3.6 秒）。初次 UI 定位把扩展名当成实际显示的所属应用名，修正为 ReceiverHost；下拉手势未关闭紧凑面板，改为真实背景点击。一次构建发现生成 Swift 插件包依赖为空、file_picker_darwin 缺失，顺序重建恢复（145.4 秒），未改 SDK/生产逻辑。最终测试日志 `/private/tmp/gemsnote-ios-outbound-cancel.log`，工程和结果 `/var/folders/6h/jjvzsttd0ms0j80_cfqgvt8c0000gn/T/gemsnote-outbound-ios.Z43McO`；独立接收应用已卸载。仅测试/脚本/文档改动；iPad、其他接收应用、真机与工作区完整分享链路仍待验收。

- 本批 Android 对外分享收尾：静态分析通过（3.6 秒），普通 APK 构建通过（10.5 秒）、覆盖安装及实际冷启动成功，随后正常关闭一次性模拟器。日志 `/private/tmp/gemsnote-outbound-{analyze,restore-build}.log`。仅测试/夹具改动，不重复此前 787 项全套及 iOS 构建。下一步验证 iOS 对外分享；现有服务端联合整改不变。

- 上批 `b07d10a` 完成 iOS 本地文件面板验证。本批 M22/M16 Android 对外分享使用生产 NoteSharer/AttachmentSharer、真实系统分享面板和独立本地接收 Activity，专项 **1 项通过（18 秒）**。精确核对 Markdown/HTML 标题与正文、两种附件的原始字节（含空文件）、安全文件名、MIME、content URI 及临时读取授权；取消后只存在四条接收记录。没有网络/真实账号或外部服务消息。初轮仅因系统面板折叠未找到接收目标失败，补上滑展开后通过，不属于生产分享缺陷。成功后测试夹具已卸载，宿主证据 `/private/tmp/gemsnote-outbound-share-expanded.log` 及 `/var/folders/6h/jjvzsttd0ms0j80_cfqgvt8c0000gn/T/gemsnote-outbound-share-_1egoe6g/received.jsonl`。本批仅测试、夹具和文档变更；阅读页/附件下载到分享的完整工作区流程、iOS 对外分享、其他接收应用和真机仍待验证。

- 本批 iOS 文件面板验收收尾：普通 `lib/main.dart` 模拟器应用重新构建通过（16.9 秒）、覆盖安装并实际启动成功（PID 3127），随后正常关闭模拟器释放内存。日志 `/private/tmp/gemsnote-ios-picker-restore.log`。仅测试/脚本/文档变动，不重复上一批已通过的 787 项 Flutter 全套和 Android 构建。

- 上批 `f838787` 修复 Android 归档选择。本批补 M22 iOS 真实文件面板验证：测试专用 Flutter 界面调用生产导入导出服务，独立 PickerFiles 测试应用提供本地 Files 目录；iPhone 12 mini / iOS 26.3 **1 项 UI 测试通过（60 秒，入口构建 20.2 秒）**，Markdown/HTML/含二进制资源归档往返校验正文、格式、标签/星标及原件，导出下拉关闭和导入取消均返回，宿主逐字节核对三份导出产物并仅清理本轮文件。iOS `.gemsnote` 在现有过滤下可选，不跟随 Android 改为任意文件；本批没有生产改动。前两轮失败分别是夹具缺少实际文件共享 plist 键/按钮语言，以及 iOS 26 导出面板没有 Cancel 按钮；已修正夹具和实际手势，不能计为应用缺陷。静态分析无问题（3.6 秒），Shell/Ruby 语法通过。最终日志 `/private/tmp/gemsnote-ios-picker-final.log`、证据 `/var/folders/6h/jjvzsttd0ms0j80_cfqgvt8c0000gn/T/gemsnote-picker-ios.QxELc9`。不代表 iCloud/第三方 provider、iPad、真机或工作区落库验收；服务端联合修复和发布暂缓不变。

- 本批文件选择器修复最终验证：静态分析无问题（3.6 秒），完整 Flutter **787 项通过、8 项条件跳过（83 秒）**，普通 Android debug APK 构建通过（13.7 秒）；已覆盖安装并实际冷启动成功，随后正常关闭一次性模拟器。日志 `/private/tmp/gemsnote-picker-{analyze,tests,apk}.log`。生产改动仅 Android 文件选择过滤，iOS 分支保持原逻辑，本批不宣称完成 iOS 文件面板验收。

- 上批 `6a8c7ee` 验证真实双账号隔离。本批 M22 用一次性 Android 35 模拟器执行真实 DocumentsUI 导出/导入，复现 `.gemsnote` 文件灰显：Android 将 custom 扩展名过滤转成已知 MIME，自定义格式无法选中。已将 Android 选择器改为任意文件浏览，仍由生产导入器严格检查扩展名、流式大小和归档内容；其他平台过滤不变。最终设备专项 **1 项通过（30 秒，集成构建 12.8 秒）**：Markdown/HTML/含二进制附件归档逐项往返、元数据/原件一致、不支持扩展名拒绝、保存和导入取消；宿主再次逐字节读取导出正文/附件并确认取消无产物，仅清理本轮唯一命名文件。不登录、不写账号数据库，不宣称云 provider、工作区落库或 iOS 文件面板已通过。证据 `/private/tmp/gemsnote-file-picker-final.log` 和 `/var/folders/6h/jjvzsttd0ms0j80_cfqgvt8c0000gn/T/gemsnote-file-picker-ptwulr60`；初始失败证据在同级 `gemsnote-file-picker-b1tzqpdc`。开发文档已补命令和验证边界。

- 上批 `176e3d6` 记录服务端联合整改。本批 M21 新增真实双账号联调：生产 AuthRepository 登录、同一 SQLite 保存两账号离线草稿和独立自动同步偏好、仓库对象重建后的离线恢复/切换、A 同步不清除 B 待同步数据、各自上传归属及双向越权读取拒绝、离线退出 B 保留 A 凭据和切换能力，专项 **1 项通过**。凭据使用内存测试实现，SQLite 为宿主实现；不冒充设备安全存储或 UI 切换验收。日志 `/private/tmp/gemsnote-api2-account-isolation.log`，临时环境 `/private/tmp/gemsnote-api2-live.6g6oZR` 已停止。最终静态分析通过（3.6 秒）、完整 Flutter **787 项通过、8 项条件跳过（72 秒）**：6 项显式联网测试及原浏览器/性能 2 项。仅测试与文档改动，没有重建未变化的原生业务产物。服务端共享复制/JWT 统一和历史更新仍按用户要求留待三端联合处理；下一步继续文件选择/对外分享及账号切换的设备流程。

- 用户明确将服务端问题留待与 Web、desktop 联合处理；已整理 [服务端后续清单](docs/SERVER_FOLLOW_UP.md)，包含 S01 API2 JWT 统一（七个已定位业务接口、全路由审计、三端适配及安全/业务验收）和 S02 PostgreSQL 历史字段映射。当前不修改服务端，也不为复制新增 Cookie 依赖。最终共享合同测试 13 项通过、5 项联网条件跳过，静态分析通过；真实复制失败仍保留。

- 本批新增真实 API2 双账号共享验收，管理员仅在一次性库内添加接收者并授权共享。正文/附件读取及拒绝修改原文已走通；token-only 复制实际返回 **302 → /login**，因此完整用例失败，副本所有权、独立附件、编辑及撤销后使用的后续断言未执行。保留失败门禁，不改为预期失败或 Cookie 回退。用户已明确 API2 统一 JWT；此前准备让复制复用 Cookie 的方案取消。现有 `_accountFormAction` 的用户名/邮箱/密码/头像/正文图片/附件上传也列入待联合整改，不能把 API2 路径等同 JWT 鉴权。服务端修改仍需授权，历史 `note_id` 更新问题亦未解决。新增夹具 Cookie 仅用于管理员建立测试数据，不进入应用业务代码。最终证据 `/private/tmp/gemsnote-api2-shared-live.log`，临时目录 `/private/tmp/gemsnote-api2-live.Zzrc1X`，用例运行器退出并清理进程。本批无生产代码改动，静态分析通过；详见 docs/API2_LIVE_TESTING.md。

- 上批 `ab589ff` 验证 iOS 真实登录恢复。本批共用场景加入 Android 宿主地址 `10.0.2.2:19090`，脚本增加已启动 emulator 校验、禁止真机、互斥平台参数与两阶段间 force-stop。一次性 Android 35 / Pixel 2 AVD 两阶段各 **1 项通过**（APK 集成构建 20.5/21.1 秒，用例各约 1 秒），同样确认新 PID、真实安全存储/SQLite、零 HTTP 离线恢复、使用恢复 token 同步、未同步退出保护及重新登录保留正文，最后清理独立测试数据；临时 PostgreSQL 已停止。静态分析无问题（3.7 秒），普通 Android APK 构建通过（15.1 秒），隔离 AVD 已恢复普通 APK 并启动后正常关闭。原 Pixel 9 首次测试在加载前 ADB 断开，guest 心跳连续停在 7；重连无效后正常退出，软件模式重启出现启动未完成/ADB 反复握手，不能计为业务测试失败或通过。使用已有镜像在 `/private/tmp/gemsnote-api2-avd-home` 创建隔离 AVD 才完成测试，没有下载镜像、清空或更改原 AVD 配置。Android 日志 `/private/tmp/gemsnote-native-api2-android-isolated.log`，临时 API2 环境 `/private/tmp/gemsnote-api2-live.gFlrt3` 已停止，原失败日志 `/private/tmp/gemsnote-native-api2-android.log`；iOS 模拟器已关闭释放内存。原 AVD 普通 APK 恢复在有限等待窗口内实际失败：ADB 安装返回 `cmd: Can't find service: package`，系统包管理服务不可用；原 AVD 可能仍留有首次安装的集成测试入口，已停止恢复尝试并正常关闭，不能声明原环境已恢复。正常 APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`，待原 AVD 恢复正常启动后需覆盖安装；本批仅测试/脚本/文档改动，不重复 Flutter 全套与 iOS 构建。服务端历史更新仍待授权修复，发布仍暂缓。

- 上批 `6fc8e98` 完成 iOS 分享语言验收。本批新增 `native_api2_session_test.dart` 和临时 API2 脚本的 iOS 模式：iPhone 12 mini / iOS 26.3 两阶段各 **1 项通过**，首阶段真实生产 AuthRepository 登录、SQLite 快照、钥匙串 token、离线笔记落盘；运行器结束首进程后，恢复阶段验证 PID 不同，禁止 HTTP 请求时恢复真实账号、待同步 Markdown 正文和已保存账号，然后使用恢复的 token 联网成功同步。继续验证未同步笔记拒绝直接退出、显式退出仅删除凭据且保留正文、重新登录保留缓存并上传富文本笔记。使用随机前缀的独立 SQLite/钥匙串键，测试内确认清除自己的凭据与数据库目录；不修改正常账号数据。集成构建分别 268.9/60.1 秒，用例各约 1 秒；静态分析无问题（4.4 秒），Shell 语法/diff 检查通过，临时 PostgreSQL 退出清理已核对。运行器已退出时 simctl terminate 返回“found nothing to terminate”是预期情况，脚本已单独处理该分支并实测，其他终止错误不忽略。普通 iOS Debug 入口构建通过（146.0 秒）。本批仅测试/脚本/文档改动，未重复 Flutter 全套及 Android 构建。日志 `/private/tmp/gemsnote-native-api2-session.log`、`/private/tmp/gemsnote-native-api2-restore.log`，临时环境 `/private/tmp/gemsnote-api2-live.5JEBmC` 已停止；不是登录页 UI、后台系统唤醒或跨账号切换验收。下一步将同一流程用于 Android 模拟器；服务端历史更新阻塞与发布暂缓不变。

- 上批 `350d600` 补强真实响应丢失证据。本批完成 iOS 主应用到 Share Extension 的显式语言跨进程验收：通过真实语言菜单英文→中文→英文，每轮终止并重启主应用后再打开独立来源应用的分享扩展，精确检查保存、取消和导入提示；专项 **1 项通过（63 秒）**，连同 Safari、混合资源及失败批次共 **4 项 UI 测试通过（122 秒）**。宿主确认原 App Group 语言偏好恢复，三次取消未新增记录，原有 PNG/bin/GIF 逐字节和文本正文验证仍通过，只清理本轮五条成功夹具及其来源文件。首次执行发现旧测试仅定位英文 Gemsnote，中文系统实际显示“珠玑笔记”，已修正正式中英文名称定位并重跑，未修改生产原生逻辑；失败的初次测试不计通过。最终普通 iOS Debug 模拟器构建通过（58.9 秒），含 `c30ecb6` API2 请求头修复。Shell/Ruby 语法及 diff 检查通过，本批测试/文档改动未重复全套 Flutter/Android 构建。UI 日志 `/private/tmp/gemsnote-ios-language-ui.log`，产物 `/var/folders/6h/jjvzsttd0ms0j80_cfqgvt8c0000gn/T/gemsnote-share-ui.vMo5GJ`，构建日志 `/private/tmp/gemsnote-api2-ios-build.log`。未验证系统语言变化、真机、后台长期唤醒；PostgreSQL 历史更新阻塞仍待服务端处理。下一步继续已登录设备生命周期及其他原生入口；发布仍暂缓。

- 上批 `05449ce` 完成目录管理真实联调。补强创建响应丢失证据：在原客户端重试前，先由第二个独立 SQLite 客户端同步并确认远端已有同一 ID 和完整正文，再验证原客户端重试后不重复创建。全新临时 PostgreSQL 专项 **1 项通过**，日志 `/private/tmp/gemsnote-api2-loss-confirmed.log`，退出后临时服务自动停止。本批仅补断言和文档，不重复已有全套回归。

- 上批 `c30ecb6` 修复 Cookie 会话请求头并建立真实 API2 测试。本批继续 M06/M07/M11 目录管理：全新 PostgreSQL 临时库专项 **1 项通过**，使用生产客户端、同步器和 SQLite 验证父子目录创建/重命名、含子目录删除拒绝（精确业务原因）、旧 USN 删除拒绝（conflict）、空子目录及父目录删除后通过正常增量同步移除；创建标签并分别用于活动笔记和回收站笔记，删除标签后收到 tombstone、两类笔记标签清空且 USN 前进，正文与回收站状态保留。最终静态分析无问题（3.8 秒），`git diff --check` 通过；仅测试和文档改动，未重复全套 Flutter/平台构建。真实 API2 当前累计三项已分别通过、一项历史更新失败；普通回归的联网条件跳过由三项增加为四项，不将它们算入已通过数量。最终日志 `/private/tmp/gemsnote-api2-catalog-final.log`，临时目录 `/private/tmp/gemsnote-api2-live.Bp4GIQ`，脚本已停止临时服务。服务端历史字段映射阻塞仍未修复；下一步继续其他不依赖历史更新的入口和生命周期验收。

- 上批 `8af797c` 完成 Android 文件分享设备验证。用户已用 brew 安装 PostgreSQL 18 并授权临时测试，本批使用全新独立 PostgreSQL 18.6 数据目录及服务端源码副本，仅监听本机；未修改服务端工作区、真实配置或数据库。实际联调发现移动端 Cookie 会话写请求缺少 `X-Requested-With: XMLHttpRequest`，附件上传被 `Api2.RequireSession` 拒绝为 `invalidRequest`；已按 desktop 代理补齐共用 `_accountFormAction`，六类接口（附件、正文图片、头像、用户名、密码、邮箱）增加断言。新增 `scripts/test_api2_postgres.sh` 不安装软件，自动构建临时副本、初始化并运行测试、退出时停止两项进程；实际执行及清理验证通过。真实 API2 **2 项通过、1 项失败**：双 SQLite 客户端创建/拉取、二进制上传下载逐字节一致、服务端已保存但响应被注入丢失后的重试不重复创建通过；后续笔记编辑失败为服务端 `historySaveFailed`，PostgreSQL 明确报告 `note_content_histories.note_id` 不存在（实际主键 `id`），完整历史恢复未执行到，保留失败测试。禁止将此归为客户端通过；服务端修复留待授权，不更改测试表结构绕过。完整 Flutter 回归 **787 项通过、5 项条件跳过（80 秒）**：原浏览器/性能 2 项及新增显式联网 3 项；静态分析无问题（最终 3.4 秒），Android debug 构建通过（7.5 秒）。日志 `/private/tmp/gemsnote-api2-script-validation.log`、临时测试目录 `/private/tmp/gemsnote-api2-live.mF77ls`，两个临时服务已停止；另一次初始目录 `/private/tmp/gemsnote-api2-live-6xu3u8gy` 也已停止。复现与限制见 `docs/API2_LIVE_TESTING.md`。下一步继续不依赖历史更新的 API2 和设备流程；历史更新/恢复需服务端修复后复验。

- 上批 `983aec2` 修复小组件重复路由。本批推进 M23 Android 文件分享设备验收：新增独立 Java 来源应用（非导出 provider + 临时 URI 授权）和 SDK 构建/宿主脚本，在 Pixel_9 / Android 35 真实系统分享面板发送 PNG、bin、GIF、UTF-8 BOM 文本及说明文字，5 条原子入队；三类二进制原件逐字节一致，正文中文/emoji/换行完整且去除 BOM，应用重启后队列保持。有效 PNG + 空 bin 失败批次在完整 17 秒观察窗口内未新增记录，原件目录无残留。夹具最初受系统大写按钮和 Android 15 状态栏遮挡影响，已修复测试来源界面并实际重跑通过，未修改生产分享逻辑。随后共用原生导入场景在 Android **1 项通过（5 类内容循环，16 秒，集成 APK 构建 13.2 秒）**，覆盖账号认领/跨账号拒绝、真实导入对话框编辑和笔记本选择、独立 SQLite 离线保存、数据库重开重试不覆盖编辑、首次确认失败后重试清理、不重复导入；宿主确认队列与私有原件目录均为空。Android 普通入口已重新构建（10.5 秒）、安装启动，来源夹具已卸载。静态分析无问题。测试场景抽为 native_share_import_scenario.dart，保留 iOS 原入口并新增 Android 入口，iOS 运行脚本补 --no-uninstall；iPhone 12 mini / iOS 26.3 的三类夹具导入专项 **1 项通过（10 秒，Xcode 集成构建 107.2 秒）**，宿主实际确认 App Group 仍可访问、queue=[] 且没有 .resource 原件。Android 模拟器已正常关闭释放内存，iPhone 12 mini / iOS 26.3 已启动；最终普通 iOS 模拟器构建通过（59.8 秒），已重新安装启动。Android 证据 `/private/tmp/gemsnote-android-share-ui-verified.log`、`/private/tmp/gemsnote-android-share-import.log`，UI records.json 在 `/var/folders/6h/jjvzsttd0ms0j80_cfqgvt8c0000gn/T/gemsnote-share-ui-efbtmq86`，记录已通过真实确认清理，不能再次按此文件导入。iOS 回归日志 `/private/tmp/gemsnote-share-common-ios.log`。本批仅增加测试、夹具、脚本和文档，未修改生产业务代码；未重复上一批已通过的 787 项完整 Flutter 回归。其他来源/云 provider、无授权 URI、后台及真实 API2 上传仍未验收。

- 上批 `c1af3fc` 已验证原生小组件列表和事件。本批增加 `android_widget_workspace_test.dart` 与宿主 `--workspace` 模式，将真实桌面点击接入生产 HomeWidgetController/WorkspacePage 和独立 SQLite。首次设备测试复现真实缺陷：小组件 URI 同时被 Flutter 默认深链处理器推送为命名路由，打开/新建报 `Could not find a generator for route`，虽原生操作成功但 Flutter 异常使测试失败。已在 Android Activity 声明 `flutter_deeplinking_enabled=false`，保留原生账号/代次校验及专用通道，不增加兜底路由掩盖错误；当前无 Flutter 深链功能，后续增强应显式设计分发。修复后 **1 项工作区设备测试通过（3 次实际桌面点击，13 秒，集成 APK 构建 21.4 秒）**：现有正文打开、阅读页未返回时延后新建、选择笔记本并采用默认 Markdown 编辑器、编辑标题/正文并保存、桌面显示新标题并重新打开正确正文、SQLite 重开后内容保留、全程 HTTP 请求数为 0。独立临时数据库在结束时清理，不操作真实账号笔记。宿主前置检查兼容运行器结束后仅保留 AppWidgetHostView 的情况，每阶段仍严格验证实际内容；测试使用 --no-uninstall。静态分析无问题，完整 Flutter **787 项通过、2 项条件跳过（74 秒）**，跳过项仍为浏览器与性能条件专项。设备证据 `/private/tmp/gemsnote-widget-workspace-fixed-final.log`；失败复现 `/private/tmp/gemsnote-widget-workspace.log`。原生八阶段回归亦通过（21 秒）；最终普通入口 APK 构建通过（10.2 秒）并已重新安装。额外确认后台进程 7442 终止后，单次桌面标题点击在新进程 7951 打开英文登录页，新进程日志无未知路由异常（`/private/tmp/widget-process-login.{xml,log}`）。这只验证未登录进程重建，不代表已登录恢复或系统长期运行。另实测 force-stop 后单次点击未进入登录页，不计为通过；Android 15 会取消 PendingIntent 并禁用强制停止应用的小组件，不能将历史“再次点击最终恢复”当作该场景保证。首次 UIAutomator 读取超时，确认原读取进程已退出后重读成功，未把快照超时算应用失败。下一步继续已登录生命周期、平台入口及真实 API2 验收。

- 上批 `3cbb276` 完成小组件未登录入口验收。本批新增 `integration_test/android_home_widget_test.dart` 与宿主 `scripts/test_android_home_widget.py`，在 Pixel_9 / Android 35 实际使用生产方法通道、SharedPreferences、RemoteViews、Pixel Launcher 和 PendingIntent，**1 项设备测试通过（8 个桌面阶段，22 秒，集成 APK 构建 13.3 秒）**。覆盖默认关闭时发布不泄露标题、开启 A 列表并点击正确 ID、关闭清空、切换 B 默认关闭且不显示 A、B 列表/新建回传、切回 A 保留开启偏好并拒绝旧代次发布、退出显示登录提示；每次确认核对 account/action/noteId，并验证错误 acknowledge ID 不清掉当前事件。宿主逐阶段核对真实桌面 XML，所有标题列表只含当前夹具；不使用真实登录、不访问网络、不写笔记数据库，尚不代表 Flutter 工作区完整导航。最终设备存储确认 account 为空、notes=[]、无 pending，两个虚拟开关均 false。首次运行 Flutter 默认卸载导致测试应用和桌面绑定消失，已添加 `--no-uninstall`、恢复正常应用并重建小组件后复跑通过；最终脚本保留安装和数据。静态分析无问题，现有小组件控制器/导航 **13 项回归通过**。开发文档已补环境、复现、清理及普通入口恢复步骤。最终普通入口 Android debug APK 构建通过（10.7 秒），已覆盖安装启动。最终日志 `/private/tmp/gemsnote-widget-device-final.log`，桌面证据目录 `/var/folders/6h/jjvzsttd0ms0j80_cfqgvt8c0000gn/T/gemsnote-widget-ui-3o24d_xr`。下一步继续完整工作区设备导航及其他原生入口验证，系统回收、其他启动器和真机行为尚未验收。

- 上批 `80c3b7d` 已完成 787 项完整回归。本批完成 M24 的首轮实际桌面验收：Pixel_9 / Android 35 安装最新 debug APK，通过 Pixel Launcher 的 Widgets 搜索 Gemsnote、展开并添加 3×3 小组件；未登录显示英文登录提示，点击“＋”进入英文登录页。通过应用语言菜单切换简体中文后，桌面立即显示“珠玑笔记”“打开珠玑笔记登录”，加号无障碍说明为“新建笔记”。强制停止应用后点击标题，首次即时快照仍为桌面，再次点击并等待后进入中文登录页，包状态 stopped=false；只确认最终能恢复，不断言首次点击即时成功。初始 2048 MiB 模拟器出现系统级 ANR 和严重内存压力，正常关闭确认退出后，以单次 `-memory 3072 -cores 2` 重启恢复响应，未清数据或更改 AVD 配置。证据 `/private/tmp/widget-{placed,create,chinese,cold-retry}.xml`、`/private/tmp/widget-placed.png`。已确认未登录入口和语言更新，已登录笔记列表、隐私关闭、账号切换和点击具体笔记仍待设备验收，不能把本批视为 M24 整体完成。本批未修改生产代码。

- 按用户要求重新检查 Xcode：外接盘 Xcode 26.3（17C529）首次启动检查通过，iOS 26.2 SDK、iOS 26.3.1 模拟器运行时、CocoaPods 1.17.0 可用。通过 `DEVELOPER_DIR` 和项目 `scripts/with_xcode.sh` 实际构建 iOS Debug 模拟器应用成功（20.7 秒）；日志 `/private/tmp/gemsnote-xcode-current-check.log`。系统默认 xcode-select 仍为 CommandLineTools，未修改全局设置；本次没有启动 iOS 模拟器。

- 上批 `5589fc0` 已补齐原生权限本地化。本轮对近期 iOS 迁移做阶段性跨平台复核：静态分析无问题，完整 Flutter **787 项通过、2 项条件跳过（86 秒）**，Android debug APK 构建通过（Gradle 8.5 秒）；Android 原生文本解码及资源存储回归通过。两个跳过项分别为显式 Chromium 浏览器专项与 SEARCH_BENCHMARK 性能基准，不计为通过。原生 Android 脚本首次受终端遗留失效 JAVA_HOME 影响，单次命令指定 Android Studio JDK 后通过，未修改系统配置。复核 HTTP 入口仍集中于 API2 客户端；Legacy 字符串只用于历史资源 ID 解析，公开头像遵守既有例外。核对恢复历史、复制共享笔记、删除笔记本的 Flutter 路径与服务端 API2 路由一致；本轮不宣称真实服务器交互已验收。docs/MIGRATION.md 已合并过期历史状态为当前证据摘要，逐批记录仍保留于本文件。下一步优先 Android 小组件/文件入口的模拟器运行验证，以及跨进程语言切换；相机、后台长期运行及真实 API2 并发仍待相应环境验收，发布继续暂缓。日志 `/private/tmp/gemsnote-migration-audit-{analyze,tests,apk,android-native}.log`。

- 上批 `e8bbe4d` 已修复 iOS 文本文件导入。本批补齐 M19/M20 原生相机权限用途说明：此前 Runner 只有英文权限说明，已有中英文名称 strings 文件未接入 Xcode 资源组，现保留既有应用名称，补齐 en/zh-Hans/zh-Hant 的权限说明并加入 Xcode Resources 和已知语言。最终 iOS Debug 模拟器构建通过（11.3 秒），实际 App 包中三种名称和权限文案已核对，已安装并冷启动；Foundation 语言选择检查 zh-CN→zh-Hans、zh-TW→zh-Hant、en-US→en、fr-FR→en 均通过。系统权限说明由 iOS 为该应用选择的语言控制，应用内 system/zh/en 不动态改写权限弹窗。真机权限弹窗、相机方向/拒绝/生命周期仍待验收；本批仅原生资源和工程引用改动，未重复 Flutter 单元及 Android 构建。

- 上批 `fa6e11e` 已验证导入对话框。本批复核 M23 文本文件兼容性：Android 严格解码 text/plain/markdown，而 iOS 系统分享 `.txt` 实测保存为 attachment，原先 UI 点击成功但新增最终内容断言失败。已补齐纯文本提供者 String/Data/临时文件 URL 和文本文件 URL 的严格 UTF-8 正文读取，256 KiB 上限、首 BOM 去除、空白/NUL/无效编码拒绝，复用分块普通文件读取且不访问远程 URL。新增 Swift 边界与原有存储/跨进程回归通过；最终 iOS Debug 模拟器构建通过（13.0 秒）。真实系统 UI 回归 **3 项通过（57.3 秒）**，最终存储核对确认 `.txt` 完整正文且无附件元数据，PNG/二进制/GIF 原件逐字节一致，失败批次无部分记录；仅清理本轮五条夹具。未改变 API2 或 Flutter 业务流程，本批原生 Swift 修改未重复 Android 构建及 Flutter 单元全套。下一步继续其余来源兼容性和平台入口验收。

- 上批 `cd90947` 已验证原生通道与离线仓库导入。本批将设备测试接到生产 `SharedTextDialog`：文本、PNG、二进制文件逐项编辑标题/正文、选择笔记本、保存；通过回调注入一次确认清理失败，验证错误显示、编辑禁用、记录仍待确认，再点“重试清理”调用真实原生确认且不重复导入。SQLite 重开后的重试仍保留后续编辑。iPhone 12 mini / iOS 26.3 **1 项设备测试通过（三类内容循环，约 10 秒；Xcode 集成构建 16.9 秒）**。过程中修复测试的 void await、模拟键盘接口及正文/笔记本搜索框定位问题，未修改生产代码。测试使用真实 App Group 与独立 SQLite，不访问服务器；不代表工作区完整导航或真实系统清理故障已验收。最终静态分析无问题，普通 iOS 模拟器应用构建通过（20.6 秒），已重新安装启动。本批仅测试/文档改动，未重复 Flutter 单元全套及 Android 构建。下一步核对其余设备入口与完整迁移清单。

- 上批 `1bbec15` 已验证 GIF 原件与失败批次。本批新增 `integration_test/ios_share_import_test.dart` 和 `scripts/test_ios_share_import.sh`，使用生产 Swift 存储写入唯一文本/PNG/二进制夹具，真实 iOS 方法通道认领、读取、确认，独立真实 SQLite 库执行生产仓库离线导入。设备测试 **1 项通过**（集成入口 Xcode 构建 74.4 秒），覆盖认领前不能读资源、外账号不能读取/改认领、待同步笔记与资源创建、数据库关闭重开后重试不覆盖后续编辑、不重复创建记录、确认后不能再读取。测试拒绝所有网络调用，不使用真实账号，不等于导入对话框或 API2 上传验收。脚本拒绝已有收件内容，失败不主动清理剩余夹具，成功仅确认自己记录和清理临时数据库；测试运行器可能卸载应用，不保证失败后容器仍可访问。最终静态分析无问题，普通 `lib/main.dart` 模拟器构建通过（149.7 秒），已重新安装启动。额外宿主文件检查在测试后未能取得 App Group 容器，不计为通过；资源确认结果以设备测试中的实际通道拒绝读取为证，不宣称核验过文件删除。下一步继续实际导入对话框交互及生命周期验收。

- 上批 `1d9a37a` 已验证 PNG/二进制文件分享。本批扩展为 PNG、二进制文件、GIF 三项真实系统分享，GIF 正确保留为附件且全部原件逐字节一致；另验证有效 PNG 加空文件时扩展报错、保存禁用、取消可用，真实队列没有部分记录。连同 Safari 回归共 **3 项 UI 测试通过（62.0 秒）**，宿主存储核对通过，仅清理本轮四条成功记录及夹具原件。首次失败是测试在错误弹窗关闭动画完成前检查按钮，改为等待按钮出现后通过，未修改生产逻辑或放宽禁用断言。测试工程构建、Shell/Ruby 语法、diff 检查通过；本批仅测试/文档改动，未重复 Flutter/Android 构建。已同步矩阵中过期的安全存储及 iOS 编译状态。下一步继续文本来源、超限/生命周期和主应用认领导入闭环，HEIC/真实相机与后台仍待相应设备验收。

- 上批 `70d739c` 已修复分享操作本地化并加入 Safari UI 验证。本批新增独立 SharingFixture 来源应用，以真实 UIActivityViewController 同时发送 PNG 与二进制文件；UI 测试实际进入扩展保存，宿主核对两条未认领记录分别为 image/attachment，资源逐字节等于来源原件。Safari 取消/重开/保存回归同时通过，共 **2 项 UI 测试通过（48.1 秒）**，本轮三条夹具记录及原件均已清理，不修改其他记录。已查看扩展截图，中文操作、提示及文件名布局正常。仅测试和文档改动；Xcode 构建测试工程、Shell/Ruby 语法与 diff 检查通过。下一步验证 GIF 等非正文图片回退、其他文本/文件来源、异常输入、主应用认领及导入闭环；不能把本轮两个普通文件的成功扩大为所有提供者和生命周期均已验收。

- 上批 `8f682cc` 已补齐 iOS 后台调度。本批实际验证中文 Safari 分享：系统自带 SLCompose 发布面板未采用自定义按钮标题，现改为 UIKit 只读预览、明确的“保存/取消”操作和始终可见的导入提示，保存期间禁用取消。完整 iOS Debug 模拟器构建通过（19.8 秒），独立 Xcode UI 测试通过（1 项、33.1 秒），覆盖打开扩展、取消、再次打开并保存、主应用重启。读取真实 App Group 队列确认完整测试 URL 仅保存一次且未认领，再通过生产存储 acknowledge 清理本次唯一记录。可重复运行脚本 `scripts/test_ios_share_ui.sh` 及测试工程生成器已加入；Ruby/Shell 语法和 diff 检查通过。本批仅原生 iOS 界面及设备测试/文档改动，未重跑未变动的 Flutter/Android 全套检查。无签名模拟器构建实测无法保存到 App Group，文档已改用默认签名构建。未验证图片、文件、多项、真实账号导入和真机；下一步继续这些独立验收。日志 `/private/tmp/GemsnoteSharingUI/share-ui.log`。
- 上批 `f07ad85` 已完成 iOS 分享资源限量读取。本批发现后台功能仍仅限 Android，现补齐 iOS BGProcessing 注册、许可标识、后台插件注册和 Dart 调度；实现统一到 `lib/services/background_tasks.dart`。资源缓存与笔记同步分别遵守账号偏好，网络约束、退出/关闭检查、SQLite 互斥和 API2 流程复用既有实现。每次运行在读钥匙串前按数据库偏好预约下次机会，锁屏读取失败不永久丢失后续机会，不降低钥匙串保护。15 分钟只是最早调度提示，不承诺固定周期。完整 Flutter 786 项通过、2 项条件测试跳过；追加最终后台/互斥专项 8 项通过；最终静态分析无问题，iOS Debug 模拟器构建（19.6 秒）与 Android debug APK（12.8 秒）通过。已重新安装并冷启动 iOS 应用，截图确认中文登录页和主引擎初始化正常；不能替代真机后台唤醒、锁屏、系统终止及长期同步验收。本批按独立功能提交，不推送。
- 独立仓库已确认：`/Users/raptor/Documents/github/gemsnote/mobile-app`，分支 develop。
- 上一批提交：`f0416df` 目录管理和在线完整历史恢复；本批补齐 iOS 分享、拍照、原生语言桥及 CocoaPods 回退配置。
- 2026-10-16 本轮完整 Flutter 测试 **780 项通过、2 项条件测试默认跳过**，静态检查无问题。Android debug APK 是此前批次构建通过，本轮没有重新构建，也未进行设备验收。
- Android 构建已恢复：曾因 Gradle 9.3.1 all.zip 损坏失败，已通过官方 SHA-256 验证并替换，补齐 NDK/SDK/CMake 后首次及增量 debug APK 构建成功。尚无真机验收证据。
- 当前结论：主体迁移及在线完整历史恢复已接入。iOS 分享扩展新增图片、文件和多项接收，实现已通过 Swift 存储测试和 iOS SDK 类型检查；完整 Debug 模拟器编译、安装和中文登录页启动已通过，完整设备验收仍未完成。
- 本轮分享相关 Flutter 测试 40 项通过。已安装 iOS 26.3 运行时和 CocoaPods 1.17.0，pod install 成功。最新环境复查：Xcode 26.3 的 Flutter doctor 检查、UIKit Swift 类型检查通过；iPhone 12 mini 模拟器约 29 秒启动成功。`scripts/with_xcode.sh` 通过单次命令的 xcrun 入口解决构建钩子丢失 `DEVELOPER_DIR` 的问题，无需管理员修改系统设置。在同一环境重新 `pub get` 恢复空的 Swift Package 依赖列表后，完整 Debug 模拟器构建通过（223.1 秒），安装、启动成功且截图确认中文登录页。初次安装曾等待 macOS 对模拟器访问 Documents 的授权，随后完成。iOS 原生集成测试 3 项通过，系统分享、相机及完整业务流程尚未验收。

### 2026-10-20 iOS 分享扩展

上批提交 `2b577a9` 已完成 Xcode 命令环境脚本和 iOS 原生集成验证。本批复核分享文件读取：原先按初始文件大小校验后一次性加载，再检查整批总量；现在从打开的文件描述符校验普通文件，并以 64 KiB 分块按剩余批次容量读取，额外探测超限，拒绝读取中尺寸变化的文件。图片分类、原件保留、API2 导入和整批发布语义不变。Swift 回归测试已通过，新增原件逐字节保留、精确容量边界、剩余批次不足、空文件、缺失文件、目录及 FIFO 不阻塞等检查；完整 iOS Debug 模拟器构建通过（102.5 秒）。本批仅修改原生 iOS 代码和文档，未重新运行无改动的 Flutter/Android 检查。系统分享面板、来源应用和扩展内存实际峰值仍待设备验收。

最新设备验证：`integration_test/native_smoke_test.dart` 在 iPhone 12 mini / iOS 26.3 **3 项通过**：App Group 收件箱真实通道、SQLite 重开与钥匙串读写、真实 WKWebView 加粗及撤销恢复原文。初次撤销断言失败，排查确认测试在原生视图挂载前执行编辑；加载后等待界面完成渲染即可通过，未修改生产编辑器、未放宽原文恢复断言。日志 `/private/tmp/gemsnote-ios-native-tests-attached.log`。最终静态分析无问题；测试后以 `lib/main.dart` 重建普通 Debug 应用（183.3 秒），已重新安装并启动。本批按独立单元提交 Xcode 命令环境脚本、设备测试与文档，不推送。下一步继续系统分享扩展来源及跨进程导入验收，不把本轮原生插件检查等同于完整功能验收。

图片、二进制文件、文件 URL、文本和网页提供者可进入原有 Flutter 分享收件箱。每批最多 8 项，资源总计最多 32 MiB；每项作为独立待导入条目依次处理。扩展预览只读，在主应用导入界面编辑。原件在提供者回调有效期内读取，存入 App Group 私有文件；账号认领后才允许读取，导入或主动丢弃确认后删除原件。

队列在跨进程锁下整批发布；数量、容量、元数据或原件失败不发布部分条目。已有文本队列可继续解码，重试保留账号认领且拒绝覆盖原件。Swift 测试覆盖批次失败、资源持久化、账号隔离、幂等、清理、损坏队列和跨进程并发。

本轮只验证存储行为、iOS SDK 类型检查和共享 Flutter 导入流程；系统分享面板、不同来源应用、扩展内存限制、App Group 签名和生命周期尚需设备验收。iOS 相机、原生语言设置及其他平台待办继续保留；未进行发布。

### iOS 头像拍照后续

已补齐 `gemsnote/avatar_camera` 原生通道和 iOS 入口：使用系统相机，显式申请摄像头权限；拒绝、无相机、重复打开和非前台调用返回错误，取消返回空值。拍照结果通过绘制归一化方向、去除原始 EXIF/位置元数据并限制为最长边 1024 像素、2 MiB 内 JPEG，再交给既有 Flutter 裁剪和 API2 头像上传流程。不保存相册副本，也不申请相册权限。

Swift 主应用、分享桥和相机实现通过 iOS 15 目标的 SDK 类型检查；Android/iOS 通道取消、错误及成功结果和头像上传专项共 14 项通过。权限弹窗、真实相机、后台中断和方向仍需设备验证；原生中英文提示尚待统一。当前终端的 `DEVELOPER_DIR` 会掩盖系统路径，复查时须用 `env -u DEVELOPER_DIR xcode-select -p`；系统真实配置仍为 CommandLineTools。

后续已接入 iOS `gemsnote/app_language`：与分享扩展通过 App Group UserDefaults 共享 `system/zh/en` 偏好，分享预览、错误与拍照错误使用该选择；未选择时中文系统显示中文，其他系统显示英文。系统相机和权限窗口保持系统控制。Swift 语言选择规则有测试，Flutter 原生语言桥测试覆盖 Android/iOS 并排除其他平台。跨进程实际偏好传播仍需设备验收。

本批静态分析无问题，全量 Flutter **781 项通过、2 项条件测试跳过**；Android debug APK 构建通过。原生语言桥追加后专项 **25 项通过**、静态分析和 Android 增量构建通过（7.1 秒），Swift 存储/语言测试和 iOS SDK 类型检查通过。完整 iOS 应用尚不能编译通过，不能据此宣布迁移完成。

下一步：系统级 Xcode 路径修正后完成模拟器构建和启动；继续核对系统分享来源、相机授权及生命周期，之后进行 Android 原生入口验收。发布保持暂缓，不自动推送。

### Android 模拟器验证进行中

本批原生功能已提交为 `408f175`，未推送。启动现有 Pixel_9 / Android 35 模拟器，首次 ADB 离线，在重连及重启 ADB 服务后恢复；`sys.boot_completed=1`，本批 debug APK 的 `adb install -r` 返回 Success。首次 `am start -W` 返回 timeout / UNKNOWN（43611 ms），UI dump 返回 null root，正在采集启动日志 `/private/tmp/gemsnote-android-startup.log`；尚不能声明启动或原生分享验收通过。模拟器进程仍在运行，不应仅因观察超时而重启或清除数据。

历史正文中的 `/api/file/getImage` 和 `/api/file/getAttach` 仅用于同源资源 ID 识别及归档引用转换；实际资源获取使用 `Api2Client` 的 `/api2/file/getImage`、`/api2/file/getAttach`，本批没有引入 Legacy API 请求。

后续诊断：首次应用进程确实存在且是前台 Activity，截图仍停在系统启动画面。日志有模拟器图形缓冲错误和多项系统服务超时/低内存回收，未见 Gemsnote 致命异常；主机交换空间使用约 7.8 GiB。已正常关闭首次实例，保留 AVD 数据并用 `-gpu host -cores 2 -no-snapshot` 重启；硬件后端识别为 Apple M4，92 秒完成系统启动。第二次应用安装返回包管理服务 `Broken pipe`，仍在核对系统日志及安装状态，不能标记应用运行通过。

### iOS 分享资源类型兼容性修正

复核 Flutter 正文图片导入器后发现它仅接受 8 MiB 内、4096×4096 内的 PNG/JPEG。扩展现在优先读取提供者的 PNG/JPEG 表示，并检查实际文件签名和 ImageIO 尺寸信息；HEIC/GIF 等其他格式、超限图片及无法读取尺寸的文件保留原件作为附件，避免保存为必然无法导入的正文图片。原件不转码、不丢弃；附件继续受原有 32 MiB 限制。此规则与现有正文图片支持范围保持一致。

Swift 测试覆盖真实 PNG/JPEG、超尺寸 PNG、其他格式、损坏头部和超过图片字节限制的附件回退，全部存储/语言测试及 iOS SDK 类型检查通过。没有新增网络调用。

该修复已提交为 `d833f13`。后续 Android 验证有新证据：包管理器最终确认安装存在；重新启动返回 `Status: ok`，首次耗时约 77.8 秒，随后截图和 UI hierarchy 确认正常英文登录页。模拟器日志中的 DeadSystemException 属于 Google 系统组件，不是 Gemsnote，不能据此宣称应用崩溃。

已在 Pixel_9 / Android 35 验证：

- 登录页英文显示；通过语言菜单切换中文，按钮和标题变为中文，原生 `app_language.xml` 保存 `zh`。
- `ACTION_SEND text/plain` 在未登录状态接收测试文本 `Gemsnote_migration_smoke_20261020`，保存至私有 `shared_text_inbox`，未认领账号。
- 强制结束应用后冷启动返回成功（约 2.4 秒），上述分享记录 ID 与内容保持不变，没有自动消费或重复新增。

截图/XML 证据暂存于 `/private/tmp/gemsnote-android-login.png`、`gemsnote-android-zh.xml` 和 `gemsnote-android-restart.xml`。这些仅证明安装、登录页呈现、语言切换与未登录文本收件箱持久化；真实 API2 登录同步、登录后的 WebView/资源操作、图片与多项系统分享、相机和后台任务仍未完成设备验收。测试文本保留在此模拟器收件箱，供后续导入验证；没有发送给服务器。

### 原生设备自动化检查

新增 SDK `integration_test` 依赖及 `integration_test/native_smoke_test.dart`。真实 Android 35 / Pixel_9 上 **2 项通过**（运行约 42 秒）：独立临时 SQLite 数据库关闭重开后标题、HTML 正文及编辑格式保留；真实安全存储写入读取并清理随机测试密钥；真实 WebView 加载生产富文本脚本后保留原文、按选区加粗、回传变更并撤销恢复。没有模拟数据库或 WebView，也没有请求服务器。

静态分析通过，测试 APK 构建安装成功。结束后重新构建正常 `lib/main.dart` 入口并安装，避免把测试入口留作手工使用的应用。命令及隔离范围见 docs/DEVELOPMENT.md。仍需输入法、复杂选区/表格/图片、外部来源文件、多项分享、相机、后台调度和真实 API2 验收。

## 功能对照索引

路径以项目根目录为基准；表中 Flutter 路径省略 `mobile-app/`，旧版路径省略 `mobile-app/legacy-android/app/src/main/java/com/github/gemsnote/`。服务端路径中的 `api/` 是控制器目录名，不表示使用 Legacy URL；实际路由以 `conf/routes` 的 `/api2/...` 为准。

状态“部分”表示仍需实现或更强验证；现有测试名称是证据入口，不能代替真机结果。

| 编号 / 功能 | Desktop 对应 | 服务端 API2 对应 | 旧 Android 对应 | Flutter 现状 / API2 | 剩余工作与验收条件 |
|---|---|---|---|---|---|
| M01 登录、退出、离线登录 | desktop-app/api/client_api.go Auth/Logout | Api2Controller.TokenLogin；api/ApiAuthController | ui/SignInActivity、service/AccountService | lib/repositories/auth_repository.dart、data/session；API2 | 核心已实现；test/data/login_flow_test.dart、cached_login_test.dart；会话过期/离线真机验证 |
| M02 版本、USN、分页同步 | desktop-app/api/version.go、sync/pull.go、push.go | api/ApiUserController、ApiNoteController、ApiNotebookController、ApiTagController | background/NoteSyncService | lib/sync/sync_coordinator.dart；API2 | 功能已迁移；新笔记首次请求持久化及稳定版本回读已实现（schema v14），防止超时重试误确认后续编辑；上传前 USN 回退预检、新建结果差异核对恢复、资源冲突副本、远端删除恢复及 Android/iOS 后台调度、前后台互斥均已实现；跨端并发及系统后台行为仍待设备验收 |
| M03 笔记离线增改、自动保存 | desktop-app/db/note_repo.go、sync/push.go | /api2/client/note/add、update | ui/edit/NoteEditActivity | data/database/app_database.dart、ui/note_editor_page.dart；API2 | 核心已实现；本地保存/后台切换测试已覆盖，输入法与杀进程验收待做 |
| M04 Markdown 工具及阅读 | desktop-app/webapi/local.go、共享前端编辑器 | ApiNoteController 正文 | ui/edit/EditorFragment | ui/markdown_editing.dart、markdown_note_body.dart；同步 API2 | 基础工具、GFM 表格/任务列表及离线行内/块级数学公式已实现；表格/任务/分隔线/公式工具、一级至六级标题及恢复正文、引用/列表重复点击切换已实现；旧版实际启用的 Markdown Extra 定义列表、软换行、脚注、标题/代码属性列表已实现；原文不被预览改写 |
| M05 富文本与表格 | desktop-app/webapi/local.go、共享前端编辑器 | ApiNoteController 正文 | ui/edit/EditorFragment | ui/visual_html_editor.dart、safe_html_note_body.dart；同步 API2 | 旧移动端功能已迁移；加粗/斜体/标题/引用/列表/链接/图片均已覆盖，并扩展常用颜色、字号、对齐、表格合并拆分与行列操作；图片支持缓存预览、在线/离线选区插入和点击缩放查看。旧端不存在图片尺寸编辑或高级 CSS 布局工具，不再列为功能缺口；Android/iOS 真实 WebView 加粗与撤销已有设备测试；输入法、复杂选区/表格及完整编辑生命周期仍待验收 |
| M06 笔记本树及离线操作 | desktop-app/db/notebook_repo.go、api/client_api.go | /api2/client/notebook/add、update | service/NotebookService | ui/notebook_dialog.dart、move_notebook_dialog.dart；API2 | 离线新建、重命名/移动、父级优先同步和创建结果不确定时的手动核实恢复已实现（schema v13）；已有笔记本远端修改核对及父级一致性处理已实现 |
| M07 笔记本删除 | desktop-app/api/client_api.go DeleteNotebook | api/ApiNotebookController.DeleteNotebook → service/NotebookService.DeleteNotebookForce | service/NotebookService | ui/workspace_page.dart；API2 | 已实现在线空笔记本删除，检查子笔记本、活动笔记、待同步修改与版本；同步消费 tombstone，响应丢失后下次同步收敛；真实跨端并发待验收 |
| M08 移动、星标、回收站 | desktop-app/db/note_repo.go、sync/push.go | ApiNoteController.UpdateNote/DeleteTrash | service/NoteService | ui/note_reader_page.dart、workspace_page.dart；API2 | 核心已实现；trash_delete_test.dart、pending_sync_test.dart；跨客户端回收站回归待验证 |
| M09 完整复制与冲突副本 | desktop-app/webapi/local.go、sync/push.go | NoteController.CopyNote、ApiNoteController | service/NoteService | domain/models/conflict_copy.dart；API2 | 手动复制、自动正文冲突副本和远端永久删除后的本地恢复副本已支持原样复杂正文与图片/附件原件的持久克隆；本地永久删除遭遇远端修改会恢复最新版供重新决定；真机与真实 API2 并发验收未完成 |
| M10 搜索、排序、所有笔记 | desktop-app/db/note_repo.go | 本地搜索，内容来自 API2 同步 | ui/SearchActivity | ui/note_search_page.dart、domain/models/note_sort.dart | 本地搜索、分页及排序已实现；结果仅加载独立摘要类型，打开时读取最新正文；2.5 万篇桌面磁盘基准 18–70ms，保留中文/任意子串匹配；手机数据量性能仍待验收 |
| M11 标签编辑与管理 | desktop-app/api/client_api.go AddTag/DeleteTag | api/ApiTagController、ApiNoteController.UpdateNote | service/TagService | ui/tags_page.dart、note_tags_dialog.dart；API2 | 新增目录、在线创建、编辑候选和清空全部标签已实现；服务端全局删除 USN/笔记联动已修复，Flutter 全局删除/重命名已接入，重命名为可重试的多请求流程 |
| M12 历史浏览恢复 | desktop-app/api/client_api.go GetHistories/GetHistoryContent | ApiNoteController.GetHistories/GetHistoryContent | service/NoteService | ui/note_history_page.dart；API2 | 正文、历史图片、离线阅读和 Markdown/富文本格式恢复已实现（schema v21）；新服务端保留历史附件并标记完整快照，客户端已接入在线完整恢复；旧版本清单未知或原件缺失时只支持正文恢复 |
| M13 共享笔记 | desktop-app/sharedsync/sharedsync.go、api/shared_api.go | api/ApiSharedController | 旧版无完整等价 | ui/shared_notes_page.dart、data/database shared cache；API2 | 安全只读列表/正文、图片/附件缓存、预览/保存/打开/分享及权限撤销清理已实现（schema v16）；共享统一只读，可经服务端复制正文和资源到本人笔记本后编辑 |
| M14 图片缓存、预览、保存 | desktop-app/service/file_service.go | api/ApiFileController.GetImage | ui/PictureViewerActivity、service/NoteFileService | ui/cached_markdown_image.dart、services/image_exporter.dart；API2 | 缓存隔离、原始字节和工作区保存业务链已有自动化证据；原生文件窗口、云 provider 与真机兼容性暂缓 |
| M15 图片上传与正文插入 | desktop-app/webapi/proxy.go | /api2/file/pasteImage → File.PasteImage | ui/edit/NoteEditActivity | services/note_image_picker.dart、ui/note_image_upload_dialog.dart；API2 | 在线原文插入、离线图片暂存、持久上传状态与中断恢复已实现；原文暂存图片确认后事务追加；可视化编辑器在线/离线选区插入已实现（schema v19，本地引用在原件确认后原位替换）；新建富文本笔记可离线插入，再安全创建笔记并上传图片，WebView 真机验证未完 |
| M16 附件上传下载、打开、分享 | desktop-app/service/file_service.go、webapi/proxy.go | Api2.UploadAttachment、ApiFile.GetAttach | service/NoteFileService | ui/note_files_page.dart、services/attachment_*；API2 | 在线上传、下载、离线保存/分享/打开已实现；附件离线暂存、持久上传状态及结果不确定时手动恢复已实现（schema v11）；工作区页面到生产服务已有组件测试，Android/iOS 独立接收端已逐字节验证二进制和空附件的分享与外部打开；其他应用及真机兼容性暂缓 |
| M17 资源任务与缓存管理 | desktop-app/service/file_service.go | ApiNote.GetNote + ApiFile | background/NoteSyncService | services/account_file_cache.dart、background_tasks.dart、ui/file_cache_dialog.dart；API2 | 账号资源下载队列已持久化（schema v10），支持重启/暂停续传、逐文件失败恢复、失效快照拦截；64MiB 缓存与任务清理已实现；Android WorkManager 和 iOS BGProcessing 按账号偏好调度，跨引擎队列互斥；自动同步开关按账号持久化（schema v20），后台笔记同步按此偏好调度；系统后台唤醒及终止恢复待设备验收 |
| M18 缓存偏好持久化 | desktop-app/db 配置、service/file_service.go | 无新增请求 | ui/SettingsActivity | app_database schema v8、workspace_page；本地 | 已提交 f524502；账号隔离、升级、读写失败/重试测试通过 |
| M19 账号资料、头像、密码 | desktop-app/webapi/background_profile.go、proxy.go | Api2.UploadAvatar、User.UpdateUsername/UpdatePwd、web/emailChange | ui/SettingsActivity | ui/account_page.dart、avatar_upload_dialog.dart；API2 + 允许的公开头像 | 主要功能、头像裁剪、Android/iOS 相机入口与 PNG/JPEG/WebP/GIF/BMP 导入已实现；iOS 原生代码通过 SDK 类型检查，原生相机权限/方向/取消/进程恢复及帐号变更竞态真机验收待做 |
| M20 默认编辑器、语言、关于 | desktop-app/webapi/about.go、应用配置 | 默认编辑器与语言本地；协议版本 API2 | ui/SettingsActivity、AboutActivity | default_editor_dialog.dart、about_dialog.dart；API2 | 编辑器/版本、Flutter 中英文与 system/zh/en 全设备语言设置已实现（schema v17）；Android 分享、拍照、小组件跟随选择；iOS 分享扩展与拍照错误提示已接入 App Group 偏好；仍需跨进程语言切换、输入法及原生入口真机验收 |
| M21 多账号快速切换 | desktop-app/app.go、db 配置 | Api2.TokenLogin、ApiUser.Info | service/AccountService、ui/MainActivity | app.dart、data/session/session_store.dart | 本轮实现切换/添加账号、登录页恢复已登录账号；保留离线修改与多账号凭据，切换前等待资源任务、重建工作区；静态检查和全量 488 项测试通过；Android/iOS 原生安全存储及数据库重开验证已通过，完整账号切换生命周期仍待验收 |
| M22 导入导出、对外分享 | desktop-app/webapi/local.go | 本地操作无需新接口 | ui/edit/NoteEditActivity | services/note_importer.dart、note_exporter.dart、note_sharer.dart | 原文导入导出及系统分享已实现；本地 .gemsnote 归档含摘要校验及持久上传队列；工作区落库/回滚有组件与数据库测试，Android DocumentsUI 和 iOS 本地文件面板已验证 Markdown/HTML/二进制归档往返及取消；两端独立接收应用已实际核对分享原文/附件及取消返回；云 provider、其他应用与真机兼容性暂缓 |
| M23 Android/iOS 分享接收 | Desktop 无平台等价 | 本地导入后 API2 笔记上传 | manifest ACTION_SEND、ui/edit/NoteEditActivity | services/shared_text_inbox.dart、Android MainActivity、ios/ShareExtension 与 Shared | Android 单项/多项接收已实现，真实跨应用 URI 授权的 PNG/bin/GIF/文本/说明文字、失败批次原子拒绝及导入对话框/确认清理已有设备证据；iOS Safari、PNG/二进制/GIF/纯文本文件混合分享已通过系统 UI、正文/原件核对、原生认领、生产导入对话框和独立 SQLite 落库验证；其他来源和真机生命周期暂缓 |
| M24 Android 小组件 | Desktop 无等价 | 本地快照，无新接口 | appwidget/NoteAppWidget、WidgetService、RedirActivity | services/home_widget.dart、Android NoteWidget；本地快照 | 最近 30 条标题列表、新建/打开入口、默认隐私关闭、账号代次隔离和退出清理已实现；仅 home_screen，不提供锁屏组件；Android 35 模拟器已验证桌面添加、未登录入口、中英更新、原生虚拟账号列表/隐私/切换/退出及实际点击回传；独立 SQLite 工作区打开/延后新建/编辑保存/再次打开通过，并修复重复深链路由异常；其他启动器、生命周期与真机验收待做 |
| M25 Android/iOS 发布与运行 | desktop-app/.github/workflows 为发布参考 | 无 | 旧 Android 构建参考 | android、ios、.github/workflows | 损坏 Gradle 包已修复，Android debug APK 已构建成功；iOS Debug 模拟器构建、安装和启动已通过，正式签名/发布暂缓，完整设备验收未完成；不自动发布 |
| M26 API2 边界与网络错误 | desktop-app/api/client.go | conf/routes、Api2Controller、api/* | 禁止复用旧请求 | lib/core/api/api2_client.dart | 未发现直接 Legacy 业务调用；JSON/表单已禁止自动重定向，真实 HTTP 测试覆盖 GET/JSON/form × 301/302/303/307/308；旧正文路径仅解析 FileId，绝不请求原路径 |

## API2 审计与接口缺口

已检查 Flutter HTTP 调用集中在 `lib/core/api/api2_client.dart`，业务字面路径均为 `/api2/`。
`domain/models/note_image_reference.dart` 识别旧 `/api/file/getImage` 只用于提取 ID 并读本地缓存，不能因此删除历史正文兼容，也不能据此宣称存在旧 API 调用。
公开头像下载是用户明确允许的例外，不是业务 API 回退。

- B01（服务端已修复）：笔记本删除校验所有权、删除状态、子笔记本和有效笔记，并写入 USN tombstone。Flutter 已接入删除确认、状态检查和 tombstone 同步。
- B02（已闭环）：API2 使用 `ClearTags` 明确表达空集合；desktop 和 mobile 均已接入。
- B03（已闭环）：共享权限统一只读，服务端拒绝共享者写入并忽略旧的可编辑权限；Web、desktop 和 mobile 均提供复制到本人笔记本后编辑的流程。
- B04：上传依赖 API2 浏览器 session；已实现一次性会话登录/身份校验/注销，未回退 Legacy。离线队列需要明确凭据获取与重试幂等。

- B06（服务端已修复）：标签删除写入递增 USN，并从引用它的笔记中移除标签。Flutter 全局删除和重命名交互已接入。

- B07（服务端合同已扩展）：历史元数据现包含 `IsMarkdown` 和文件清单；mobile 已恢复编辑器格式，已补服务端原件保留和在线完整恢复；升级前已丢失的文件仍不可找回。

当前服务端合同修复提交为服务端 `838d358`；desktop 对应提交为 `2f9e748`，mobile 对应提交为 `4612e3c`。

## 恢复与验收规则

每轮先读本文件与 `git -C mobile-app status --short`，核对当前源码。每项独立功能审查 diff、静态检查、相关测试，定期全量测试和 Android 构建；失败如实记录并修复。不得将未验证的平台行为记为完成。
提交前明确暂存路径并检查 cached diff。提交 hash 在下一次功能更新时记入本文件，避免为写自身 hash 反复追加提交。
主体迁移以及笔记本删除、全局标签删除/重命名已实现；在线历史附件集合恢复已接入支持完整快照的服务端。设备验收、iOS 原生实现和发布继续保持可追踪；它们没有被客户端单元测试冒充完成。

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

## M16：离线附件原件与上传恢复（2026-10-13）

- 图片与附件页面增加“离线添加附件”，支持尚未同步的新笔记；账号菜单/笔记内可查看暂存任务、导出原件、逐项上传和确认移除。暂存不联网、不索取密码、不自动上传。
- schema v11 独立保存原件与 pending/uncertain/uploaded 状态，账号和服务器隔离；下载缓存清理、配额淘汰、重新同步和笔记删除均不级联删除原件。孤立任务仍可从账号菜单导出或移除。全账号合计上限 64 个/64 MiB，拒绝超额而不淘汰未上传文件。
- 上传仅在当前笔记保存/所有权/当前账号密码验证成功且即将发送文件时持久写入 uncertain；写入失败不会发文件请求。收到成功附件 ID 后先保存 uploaded，再尝试刷新。刷新失败不回退为可重复上传。
- 请求中断或成功响应未持久保存时保留 uncertain 和原件；用户查看服务端列表、明确确认后才允许重试。API2 尚无幂等键，不能假称自动去重；不会保存密码或会话 cookie。
- 复用同步互斥锁，上传期间禁止重复上传、移除任务、重试状态切换、重置同步和退出。仅上传目标笔记正文，不顺带同步其他笔记。
- 测试覆盖数据库重开、服务器重置、账号隔离、容量上限、v10 升级、丢失响应、刷新失败、正文冲突、上传互斥，以及离线界面和危险操作确认。静态检查通过，完整 Flutter 回归 539 项通过，Android debug APK 构建通过（48.6 秒）。没有原生设备验收证据。

## M15：离线正文图片与插入恢复（2026-10-13）

- 编辑器提供“离线暂存图片”：先保存当前草稿，再将经过 PNG/JPEG 解码、尺寸与容量限制、PNG 重编码的图片原件持久保存；暂存不联网、不把临时路径写入正文。账号菜单“本地待上传资源”统一管理图片与附件。
- schema v12 增加资源种类；旧 v11 附件及状态完整保留。图片请求发送前记录 uncertain，成功响应先记录已上传 ID，再将引用追加到最新正文末尾。正文写入与 inserted 标记同一事务提交；重试插入不会重复追加，正文变化不会被旧快照覆盖。
- 已上传但未插入的图片可仅恢复本地插入；未知结果不猜测 ID、不自动重发，提醒用户可能产生孤立资源。已插入的自有图片原件可在笔记同步前供本地阅读/预览，仍校验账号、笔记和同源引用。
- 尚未同步的新笔记也能从阅读页进入图片与附件，默认只读取本地列表，支持离线添加附件。
- 新增并发正文变化、插入事务回滚、缺失/回收站恢复、未知结果、重复插入、v11 升级、编辑器暂存顺序、凭据隔离与队列恢复界面测试。
- 静态检查通过，完整 Flutter 测试 547 项通过，Android debug APK 构建通过（19.4 秒）；iOS 与发布未执行。

## M23：Android 图片与二进制附件分享（2026-10-13）

- 扩展 SEND/SEND_MULTIPLE 和 content URI 接收，支持纯文本、PNG/JPEG 图片及其他二进制附件；图片可以选择普通附件模式保留原始文件。仍拒绝自身 provider、任意文件路径，不新增媒体/存储权限，不持久持有来源授权。
- 原生原件采用随机 ID 私有路径，最多 32 MiB/文件、96 MiB/暂存目录，最多 8 项待导入；fsync 后保存队列。最多 2 个读取 worker，15 秒超时拒收迟到结果，文件暂存和清理互斥，保留已入队/在途原件。
- 账号认领后才能通过 bridge 按 ID 读取；笔记和资源 outbox 单事务导入，写入失败回滚笔记、保留原生分享。ack 失败重试不会重复创建笔记或附件；不会联网或自动上传。
- 测试覆盖原件重开、容量/超时取消/路径限制、在途清理、资源元数据与长度验证、导入事务回滚、重复导入保留后续编辑，以及图片/普通附件模式。JVM 测试通过，完整 Flutter 554 项通过；原生 URI 授权与 provider/生命周期仍待设备验收，iOS 按范围暂缓。

本批收尾：静态检查无问题，Android debug APK 最终构建通过（3.8 秒）；JVM 资源测试通过，完整 Flutter 测试 554 项通过。没有新增设备验收证据。

## M06：离线新建笔记本及创建结果恢复（2026-10-13）

- 新建/新增子笔记本改为先保存本地，可立即建子级和笔记、修改名称与位置。schema v13 持久保存 pending/uncertain/complete 创建状态及本地到远端 ID 映射。
- 同步按最终父子依赖顺序上传，确认返回名称、父级、排序和有效 USN 后，在一个事务内替换笔记本 ID、重映射子级和笔记并确认任务；不会推进全局游标。旧页面的 ID 在笔记新建、编辑、查询和分享导入时仍可解析。
- 服务端创建无幂等键（B05）：请求前持久标记 uncertain，响应丢失或本地确认失败不自动重发，冻结该笔记本改名/移动，原有子级与笔记完整保留。笔记本菜单提供“创建状态与恢复”，先读本地状态；用户主动查询服务端匹配项后可确认关联，或核实后显式恢复待创建状态。
- 图片/附件上传先同步目标笔记本的必要父级，再上传目标正文；不会创建无关的待同步笔记本。
- 数据库/同步测试覆盖重开、父子顺序、全量 ID 映射、旧页面编辑、响应丢失、事务回滚、账号隔离、父级未同步、请求期间编辑、异常响应和 v12 升级；UI 测试覆盖离线新建、重复提交、恢复确认和不自动联网。
- 静态检查无问题，完整 Flutter 测试 654 项通过（另 1 项性能基准默认跳过），共享资源专项 18 项通过（含后来新增的配额淘汰测试），Android debug APK 构建通过（10 秒）。服务端未修改，创建幂等键仍是后续可改善的接口能力。

## 2026-10-13 新笔记创建重试一致性

- schema v14 保存按账号/笔记隔离的首次创建请求；断网、进程重启及本地确认失败后均重放同一 ID 和同一正文，不保存凭据。
- API2 AddNote 响应会回显本次请求、遗漏正文，即使该 ID 早已存在。现在创建后通过正文前后两次元数据读取确认稳定 USN，核实实际内容后才确认；后续编辑再按已知 USN 更新，初始回收站状态也在创建后上传。
- 回读不一致时保留草稿与请求记录，不自动覆盖远端；此类差异的人工恢复交互仍待补齐，不能视为全部冲突处理完成。
- 完整 Flutter 测试 577 项通过，静态检查无问题，Android debug APK 构建通过（9.1 秒）。新增测试覆盖响应丢失后重启、并发编辑、回读失败/差异、事务确认失败、升级及账号隔离。

## 2026-10-13 合并表格编辑

- 可视化编辑支持有界 rowspan/colspan、向右/向下合并、拆分及合并表格中的行列增删。合并保留两侧内容；删除跨行单元格起始行时，把仍跨越下一行的内容保留下来。
- 基于逻辑网格校验重叠、缺格和跨表头分区，拒绝不规则修改，不静默丢弃正文。保持现有 20 行/10 列限制、快照比对、撤销和删除确认。
- 584 项 Flutter 测试通过，静态检查无问题，Android debug APK 构建通过。真实 WebView 输入法/选区与复杂表格阅读布局仍未验收。

## 2026-10-13 Android 桌面小组件

- 原生 RemoteViewsService 提供可滚动的最近 30 条笔记标题列表，点选打开离线正文，点击加号选择笔记本后使用默认编辑器新建。仅注册 home_screen 小组件，没有后台网络请求或正文摘要副本。
- 标题显示默认关闭，在应用账号菜单“桌面小组件”中显式开启；按账号保存开关。账号切换/退出更新原生账号代次并清空列表，较晚返回的旧账号读取不能重新发布，原生适配器也校验账号代次。
- 入口先校验当前账号和本地笔记；已有编辑页面未退出时保留操作，不打断保存。持久待处理入口按 ID 确认，重复通知不重复打开/新建。原生标题长度/条数均有上限，不保存令牌、密码或正文。
- Flutter 测试 597 项通过，静态检查与 Android debug APK 构建通过。真机待测：添加/缩放/删除组件、多组件滚动、冷启动与进程被杀、桌面重启、锁屏/解锁和不同厂商启动器。不能把编译通过视为这些已验收。
- 平台实现依据：[Android collection widgets](https://developer.android.com/develop/ui/views/appwidgets/collections)。

## 2026-10-13 合并表格原生阅读

- rowspan/colspan 按逻辑网格显示，支持变高单元格、整行被跨度覆盖、短行补空格和横向滚动；长正文决定行高，不裁切合并单元格内容。
- 保留表头与标题、可选文字及原有媒体读取限制。不规则、跨分区或超限表格退回可读文字，原文不变。
- 完整 Flutter 测试 601 项通过，静态检查与 Android debug APK 构建通过。没有引入 WebView 网络加载或新依赖。

## 2026-10-13 上传前同步版本回退预检

- 在增量/完全同步写入、仅上传、图片/附件上传以及标签/在线笔记本写入之前，读取 API2 同步状态。低于当前账号已知 USN 时停止，保留草稿、笔记本待处理状态和游标，创建请求也不进入已发送状态。
- 已知版本取下载游标、笔记、笔记本和标签的最大 USN，覆盖“上传已确认但下载游标未推进”的情况；不会用其他账号或共享所有者的版本进行比较。干净账号的仅上传/退出流程仍不发网络请求。
- 完整 Flutter 测试 609 项通过，静态检查与 Android debug APK 构建通过。
- 服务端后续需求：仅凭 USN 无法识别“恢复旧备份后版本号又增长到原值以上”，也无法原子阻止预检后发生的服务器恢复。需要服务端实例/同步世代标识及写入条件校验；本次不修改服务端。

## 2026-10-13 头像裁剪和 Android 拍照

- 选图后可拖动、缩放及居中重置，确认后生成 256×256 PNG 再进入身份验证与上传；取消裁剪不会发送请求。支持 PNG/JPEG/WebP/GIF/BMP，动态图片取第一帧，重新编码移除原始元数据。
- Android 相机使用系统拍照应用和限定私有目录的 FileProvider，不申请图库或相机权限。捕获文件最多 16 MiB/8192 边长，原生采样到约 1024 像素并处理 EXIF 方向，再进入同一裁剪流程；本地选图沿用 2 MiB/4096 边长限制。
- 每次 Activity 使用独立临时文件，活动拍摄文件不会被旧 Activity 清理；完成/取消后撤销 URI 授权并删除，进程重启清理失去回调的残留，用户可重新拍摄，不会自动上传旧照片。
- 完整 Flutter 测试 614 项通过，静态检查与 Android debug APK 构建通过。真机相机应用兼容、方向、进程被杀后的返回仍待验证；iOS 原生拍照按要求暂缓。

## 2026-10-13 Markdown 公式与编辑工具

- 使用离线 Flutter 字体/排版支持 `$...$`、`$$...$$` 及括号式 TeX 分隔符；支持多行公式、横向滚动和长按查看可选原文。代码块、行内代码、转义美元与普通金额保留 Markdown 原义。
- 不运行原始 HTML/脚本或加载远程公式资源。限制公式长度、嵌套、展开和尺寸，未知/不支持的 TeX、外链命令或超限公式显示原文，笔记正文保持不变。
- Markdown 工具栏新增表格、任务列表、分隔线、行内公式和公式块；插入表格/分隔线保留被选正文，公式包裹后保持可编辑选区。
- 新增 flutter_math_fork 与直接 markdown 依赖，沿用原有 pub 镜像及无关插件版本；vector_graphics_compiler 的约束要求 xml 从 7.1.0 调整为 7.0.1。完整 Flutter 测试 622 项通过，静态检查及 Android debug APK 构建通过。
- 实现参考：[flutter_math_fork 官方包文档](https://pub.dev/packages/flutter_math_fork)。不等同于完整 MathJax 扩展集合或流程图等其它 Markdown 扩展已迁移。

## M10 搜索结果内存与读取一致性

搜索页使用独立 `NoteSearchResult`，SQL 仅返回 ID、标题、更新时间和格式，不把正文带入列表，也不能误把摘要保存成空正文。保留已有增长前缀分页与字面 `%/_/\` 匹配。点击时按账号/笔记 ID 重新读取最新完整记录，排除已删除/回收站记录；连续点击去重，切换关键词/离开页面后丢弃过期读取，读取失败可再次点击重试。

2026-10-13 在本机临时磁盘 SQLite 中创建 25,000 篇笔记、每篇约 4KiB 正文，通过 `test/performance/search_benchmark_test.dart` 的显式开关复现：`flutter test --no-pub --dart-define=SEARCH_BENCHMARK=true test/performance/search_benchmark_test.dart`。六次采样，普通标题 18–21ms，稀有正文 49–50ms，中文 67–70ms，不存在关键词 48ms，字面特殊字符 47–49ms。1,001 条结果避免传递 4,101,197 个正文字符。临时数据库自动清理，不设依赖硬件的通过阈值。此结果不代表手机耗时或冷启动磁盘结果；保留现有子串语义，未引入会改变中文/子串匹配的分词 FTS。完整 Flutter 测试 622 项通过；性能基准额外 1 项通过。无服务端改动。

## M05 常用富文本样式

增加文字颜色、高亮、字号、删除线、段落对齐和清除格式工具；可视化编辑允许限定的 CSS 与旧 `font` 标签，原生阅读对应支持颜色、字号、常用本地字体、字重、斜体、装饰及块级/单元格对齐。合并单元格同样保留支持的样式。原文未编辑时仍原样返回；未支持的声明不自动删除或改写，编辑器保持源码模式，阅读器忽略其样式并保留文字。外部资源 CSS、脚本表达式、未知布局声明、超大字号、事件属性仍不能进入可视化编辑；CSP 与禁止网络规则不变。

`test/rich_text_style_test.dart` 覆盖支持范围、注入/边界、旧格式兼容、颜色单位和原生对齐布局。全量 Flutter 627 项通过、1 项性能基准按默认开关跳过，静态检查无问题，Android debug APK 构建通过（7.0 秒）。WebView 原生选区/撤销及输入法仍需真机验证。高级 CSS 布局、可视化图片资源插入仍列为未完成，不以样式子集冒充整个 M05 完成。

## M12 历史图片与恢复边界

数据库升级到 v15，新增按账号/笔记/历史 ID/文件 ID 隔离的 `history_images`。历史页提取真实 Markdown 图片节点或 HTML img 引用（不将普通链接/Markdown 代码块作为图片）；旧正文地址仅解析 FileId，实际下载固定使用 API2。同源正文引用才提供下载按钮；下载前通过 `/api2/note/getHistoryContent` 再次核实历史版本及正文完全一致，然后通过 `/api2/file/getImage` 读取，沿用无重定向、8MiB、15秒和图片类型限制，并解码验证。不会发起外部图片请求或使用当前资源列表冒充历史版本。

缓存与当前图片/附件共用全账号 64MiB 配额，纳入统计/清理；清理、历史正文变化、历史列表移除、笔记删除都能使迟到结果失效。同一历史版本列表刷新保留缓存；并发重复下载合并；恢复正文后仍能读取已经缓存的历史图片。未下载或服务端已删除的图片保留占位/原引用，离线模式不发起网络下载。恢复确认明确说明不会恢复附件列表；服务端缺失完整资源/格式快照记录为 B07，不修改服务端。

全量 Flutter 测试 633 项通过，1 项性能基准默认跳过；随后历史页测试 5 项通过（新增在线主动下载、离线禁止下载两项）。覆盖 API2 归属复核、外部链接/代码排除、缓存配额与清理竞态、恢复保留原文、v14 升级；修复了测试发现的下载 Future 清理回调自引用问题。原生设备表现仍需真机验收。

本批次静态检查无问题，Android debug APK 构建通过（6.9 秒）。

## M13 共享图片与附件

API2 共享快照现在解析并校验 `file` 条目，按 NoteId 关联，拒绝无所属笔记、重复及无效元数据；共享文件列表随账号缓存。数据库升级 v16，新增独立 `shared_files`，共享笔记撤销通过外键清理其文件，保留未变化的版本缓存；同一全账号 64MiB 配额涵盖当前资源、历史图片与共享资源。

下载固定使用 `/api2/shared/notes/{noteId}/files/{fileId}`；前后核实共享正文版本及权限，校验响应 SHA-256、本地计算摘要和快照长度，禁止重定向，限制图片 8MiB/附件 32MiB。JSON 附件凭合法摘要正常处理，服务端 JSON 错误响应不能作为附件缓存。权限拒绝清除共享正文与资源；正文版本变化撤销旧缓存，文件变化使对应资源失效；离线仅显式读取缓存，在线失败不自动回退。缓存清理/新快照/撤销后旧下载不能重新填充缓存，账号数据彼此隔离，下载并发去重。

共享阅读页支持正文图片主动下载与离线显示，新增只读图片附件入口，提供图片预览、文件保存、附件外部打开和系统分享，无个人笔记上传/编辑入口。文件写权限与共享成员管理没有混入只读资源实现，仍在 M13 保留为后续项。离线仍无法获知服务端已经发生的权限变化；客户端不会声称已导出到外部应用的文件可被撤回。

全量 Flutter 654 项通过、1 项性能基准默认跳过，随后共享资源专项 18 项通过（含新增全局配额测试）；静态检查无问题；Android debug APK 构建通过（10.7 秒）。只将现有 crypto 3.0.7 从间接依赖改为直接依赖用于 SHA-256，未升级其它依赖。未修改服务端或 iOS 原生代码，未发布。

## M20 中英文与应用语言（2026-10-14）

Flutter 界面、文件选择/保存标题、已知业务错误和编辑器提示提供中文 / 英文。默认跟随系统，中文系统使用中文，其它语言回退英文；登录页和账号菜单可选择跟随系统、简体中文或 English。schema v17 将语言独立保存在设备级 app_preferences，跨账号、退出、重新同步与重启保留。加载/写入失败可重试，旧异步读取不会覆盖新选择。语言设置不替换笔记内容、用户标题或插值参数。

Android 原生分享/拍照提示和桌面小组件使用同一选择，通过独立 SharedPreferences 镜像支持应用未启动时的入口；更新失败显示重试提示，不重启 Activity 或丢弃编辑器状态。小组件响应系统语言变化。系统文件面板自身语言由系统控制。iOS 原生部分保持暂缓。

新增 AST 文案迁移辅助工具、双语目录和生成说明；测试校验目录生成一致性、占位符保留、系统语言回退、实时切换/重启、保存失败、异步竞态、导出保留用户文件名、窄屏大字体、原生通道参数及 v16 升级保留草稿。语言弹窗改为滚动布局。新增 flutter_localizations / intl；开发工具 analyzer 的 package_config ^2.0.0 约束要求该间接依赖从 3.0.0 调整为 2.2.0，未升级其它既有插件。

本批完整 Flutter 回归 **664 项通过、1 项性能基准跳过**，语言专项 9 项通过，静态检查无问题，Android debug APK 构建通过（7.5 秒）。尚未进行中英系统、第三方文件面板、相机与桌面小组件的真机验收。

## M06 已有笔记本远端修改恢复（2026-10-14）

待同步且已有远端版本的笔记本菜单增加“核对远端修改”。打开只显示本地状态，用户主动读取后显示远端名称、父级与版本；保留本地或采用远端都需要明确确认。应用选择前重新读取 API2 快照、校验账号/本地版本/远端版本及必要父级；与同步和资源上传共用互斥锁，USN 回退预检仍生效。

保留本地仅更新重试基准并保留 pending，下一次同步仍以该 USN 乐观并发写入，再次冲突不会覆盖远端。采用远端在同一事务内刷新目标及必要的无本地修改父级，支持远端反转父子关系；不替换笔记正文或其它待同步修改，不推进全局游标。新父级写入、目标更新有任何失败均整体回滚。已有待同步父级保持原样，若最终层级缺失或成环则拒绝选择。

远端删除、不可用或异常回退继续保留本地数据并提示核实，不借此实现未明确的笔记本删除语义（B01）。未修改服务端或 iOS。专项覆盖持久重开、版本/账号变化、同步互斥、并发编辑、未知/变化父级、脏父级循环、干净父级反转、原子回滚、确认取消和重复提交，以及恢复后上传/再次冲突。**18 项专项通过，682 项完整回归通过、1 项性能基准跳过；静态检查无问题，Android debug APK 构建通过（7.8 秒）。**

## M05 可视化图片预览与插入

富文本编辑器允许常规 `img` 属性，保留原始地址、替代文字和尺寸；未知属性、事件、`srcset`、内联图片样式及危险协议继续使用源码模式。现有图片只读取账号授权的本地缓存，解码为 PNG 后通过编辑区域以外的样式表显示；CSP 阻止原始外链请求，不把临时标记或图片字节写进正文。缓存缺失保留占位，单页最多 32 张、8MiB 编码数据，单图像素和解码输入均有限制。

新增选区后插入图片工具，上传前冻结编辑并持久保存最新正文，沿用现有 API2 上传及身份校验；成功后在选区末尾插入引用并立即保存，保留选中文字，支持撤销重做。图片预览与正文分离，表格操作、保存和撤销无需清理临时 DOM 属性。该批完成时离线图片暂存仅使用原文编辑入口；后续已补充可视化离线选区插入，见下文。

验证：图片策略/缓存专项 6 项通过；完整 Flutter 测试 685 项通过、2 项条件测试默认跳过；静态检查无问题；Android debug APK 构建通过（7.2 秒）。`test/visual_editor_browser_test.dart` 可用 `VISUAL_EDITOR_BROWSER` 指定本机 Chromium 系浏览器，检查真实 JavaScript 的选区插入、撤销重做、外链隔离及正文完整性。本机使用已有 Vivaldi 运行该专项，1 项通过；这是开发测试工具，产品不调用或依赖 Vivaldi，未设置环境变量时跳过该测试。Android 产品使用系统 WebView，浏览器测试不能代替 WebView 的真机兼容性、输入法和生命周期验收；iOS 实现及发布仍暂缓。

## M02 新建结果差异的手动恢复

当创建回读与原请求不一致时，同步错误指向笔记菜单“核对新建结果”。界面显式联网读取、展示两端标题、笔记本、版本、格式、标签、星标及可展开的完整原文，不执行远端写入。用户确认保留本地后，再次读取稳定远端快照；确认期间账号、任一端内容或版本变化均拒绝旧选择。失败清除已核对状态，要求重新读取。

恢复在同一 SQLite 事务中只接受远端基础 USN 并删除首次创建请求记录，保留本地正文、待同步标记、图片引用和附件原件，不改变账号同步游标。重启后使用同一 NoteId 走常规条件更新，不再次创建；远端附件沿用现有 API2 更新保留逻辑。沿用同步互斥及服务端 USN 回退预检；事务失败不产生半恢复状态。没有旧请求记录的历史草稿也能核对恢复。

目前提供“保留本地并恢复同步”，不隐式采用远端或生成缺失资源的副本。远端已删除、回收站、身份不匹配和无效版本继续保留本地；本地空标签而远端非空时受 B02 限制，拒绝承诺服务端不能完成的清空操作。删除与完整资源冲突仍列为后续工作。iOS、发布及服务端未修改。

本批验证：新建/恢复数据库专项 26 项、界面专项 2 项通过；完整回归 702 项通过、2 项条件测试默认跳过；静态检查无问题，Android debug APK 构建通过。新增覆盖重启后同 ID 条件更新、本地及远端变化、账号错配、删除/回收站/错误版本、事务回滚、空标签限制、同步互斥、附件原件保留、服务端回退，以及界面取消与失败后重新读取。

## M09/M22 带资源复制与归档

个人笔记“复制”现在显式读取稳定的 API2 正文和文件清单，取回全部已归属的图片与附件原件，再用单个 SQLite 事务保存新 NoteId、原样正文、复杂 HTML 与原件上传任务。已暂存或由历史恢复的正文图片也会加入；缺少正文图片原件时拒绝生成不完整副本。源笔记、缓存和同步游标不因复制改变。归档时也只读取资源清单，不会轮换或删除源缓存；本地编辑、远端版本/清单、暂存任务并发变化会拒绝旧快照。

新增 `.gemsnote`（应用自身的 JSON 格式）导出/导入，保留标题、原文、格式、标签、星标和原件字节，逐项 SHA-256 校验。可导入当前账号或其它服务器的新笔记本，原件进入持久队列；上传确认后按原始来源和 FileId 原位替换正文中的图片/附件地址，不追加重复图片。支持重启后的原始来源图片本地预览，确认步骤仍复用现有上传身份验证和不确定结果恢复。外部非本账号资源链接只保留原文，不主动抓取网站。归档限制为原文 8 MiB、资源总计 32 MiB、最多 64 项，JSON 文件不超过 64 MiB；失败整笔回滚。桌面端目前只导出源码文件，本格式不声称与其互通。

已核对 `Note.CopyNote` 服务端 API2 路由：个人复制只创建新 NoteId/正文，不克隆图片或附件；客户端因此使用 API2 读取原件、本地持久队列和已有上传流程。正文冲突时先比对被审阅的远端版本与资源清单，取回本地正文对应的旧原件，再在单个事务中建立本地副本、暂存原件并采用远端原笔记；创建响应丢失后复用同一副本 ID。资源缺失、归档超限或事务失败时保留原本待同步笔记，不采用远端。副本在资源上传确认前仍引用原地址，上传后原位替换；外链与未识别资源不伪装成已打包。删除冲突尚需继续迁移；共享编辑服务端竞态见 B03。

本批验证：资源归档格式、摘要篡改拒绝、来源隔离、复杂正文原位替换、跨服务器导入/重启预览、原件上传后 USN 接续、本地编辑保留、文件清单/版本/暂存任务竞态、事务失败回滚及 schema v17→v18 升级均有专项覆盖。完整 Flutter 测试 **724 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。Android 文件面板和真实 API2 服务器交互尚未真机验收；不能以本地模拟替代。

自动资源冲突副本追加验证了远端版本采用、本地完整副本及原件暂存、创建响应丢失重试、暂存失败整笔回滚、旧原件缺失时保持本地待同步。完整 Flutter 测试 **728 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过；真机与真实 API2 并发验收仍待完成。

远端永久删除时，API2 正文已被服务端移除；客户端对删除标记做两次稳定读取，只从本地缓存和暂存任务取回本地原件。全部原件齐备时以单个事务创建可同步的恢复副本并移除本地旧 ID；图片或附件链接缺少原件时保留原待同步笔记。专项测试覆盖资源齐备、缺失、未列出的附件引用及删除标记版本变化。该批完整 Flutter 测试 **733 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。

本机永久删除遇远端 USN 冲突时，不以新 USN 自动重试删除。若远端已有删除标记，就确认本地删除；若远端修改了正文或元数据，则在核对本地待删状态后恢复远端最新笔记，并提示用户查看后重新决定是否删除。同步失败时也立即刷新本地列表，避免恢复项仍被界面隐藏。专项测试覆盖远端修改和远端已删两种路径；完整 Flutter 测试 **735 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。

## M05/M15 可视化离线选区插图

已有远端 ID 的笔记可在富文本编辑器选择“离线插入，稍后上传”。原件进入账号隔离的持久队列，选区中的临时 API2 形状引用只从本地队列预览。schema v19 标记这类本地选区引用；确认原件上传前，笔记同步拒绝发送临时地址，上传时先检查远端版本，上传确认后在本地事务中原位替换为真实 FileId，再允许正文同步。远端版本已变化时不会上传原件；不确定的上传结果沿用原任务的手动核对流程。本批实现时新建笔记仍需先获得远端 ID，后续已由本文末尾的新建笔记分阶段同步方案补齐。

专项覆盖本地预览、同步拦截、原件确认与重复插入幂等、远端版本变化、新建笔记限制及 schema v17/v18 升级。完整 Flutter 测试 **739 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。选区、输入法、进程中断和文件面板的 Android 真机验收尚未完成。

待上传的可视化图片只暂缓所属笔记，上传循环继续处理其它待同步笔记；结束时仍提示原件待处理，不会把临时地址送到服务端。新增双笔记回归覆盖其它笔记上传成功、原笔记仍待同步及图片确认后的重试。完整 Flutter 测试 **740 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。增量下载游标仍需避免越过未解决的同一笔记远端变更，因此该轮在上传后报告待处理状态。

## M04 Markdown 工具栏格式切换

标题、引用、项目列表、任务列表和有序列表现在可在重复点击时移除所选行的格式；混合选区先为缺少标记的行补齐标记，有序列表先重新编号。格式化仍只修改选中的整行，并保留选区或把单点光标移到同一文本位置。专项覆盖重复点击、混合选区、重新编号与光标。该批完整 Flutter 测试 **744 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。

加粗与斜体也支持再次点击取消；加粗正文上添加斜体时识别相邻星号数量，避免误删已有加粗标记。正文选区、完整表达式选区和空光标均有回归覆盖。最新完整 Flutter 测试 **747 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。

## 自动同步偏好持久化

自动同步开关由短暂的页面状态改为账号隔离的本地偏好；schema v20 从 v19 升级保留已有资源缓存偏好，旧账号默认关闭自动同步。资源缓存与自动同步两个开关分别更新自己的字段，避免互相覆盖。重启或切换回账号后恢复设置，笔记同步仍只在前台每分钟按原有条件执行。专项覆盖跨账号、重开、快照替换、升级和页面重建。该批完整 Flutter 测试 **750 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。

## M17 Android 系统后台资源下载

开启自动缓存后，Android WorkManager 注册需联网的 15 分钟周期任务；应用转入后台时，先取消并等待前台下载队列收尾，再安排一次性续传。后台 isolate 重新读取当前活动账号和安全存储中的会话，确认自动缓存仍开启后，通过原持久队列与 API2 下载；账号切换、退出或关闭偏好会使后续文件停止处理。前后台队列通过 SQLite 中带过期时间的运行锁互斥，进程中断后可以重新取得锁；原有文件版本、账号归属、缓存配额及下载确认规则继续生效。WorkManager 的实际执行时间由 Android 决定，不能保证每 15 分钟精确运行。

专项验证并发运行者只能取得一个锁、旧锁过期可恢复、已完成文件无需重下。该批完整 Flutter 测试 **752 项通过、2 项条件测试默认跳过**，静态检查无问题；最终依赖锁文件下 Android debug APK 构建成功，合并 manifest 包含 WorkManager JobService。按用户要求暂不做真机或模拟器验收。笔记上传/同步在后续批次交给 Android 系统后台任务。

## M05/M15 新建富文本笔记离线选区插图

本地新建的富文本笔记也可先在选区插入离线图片。同步时先从首次创建请求的正文中安全移除未上传图片节点，以稳定的 NoteId 创建远端笔记；本地完整正文和原件保留为待同步状态。取得远端 USN 后，用户在附件待上传列表确认上传图片原件，原位替换本地临时引用，再以正常乐观并发更新正文。创建响应丢失时重放同一份已净化请求；不能识别为图片节点或仍残留临时引用时拒绝创建。新建笔记的编辑器图片入口直接采用离线模式，避免提供无法完成的即时上传选项。

专项覆盖创建后保留本地正文、服务端不接收临时地址、图片确认后更新、创建响应丢失重试及异常引用拦截。完整 Flutter 测试 **754 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。按用户要求，设备上的 WebView 选区/输入法操作暂不验收。

## M02 Android 系统后台笔记同步

自动同步开启且应用转入后台时，注册需联网的 WorkManager 一次性与 15 分钟周期任务；恢复前台时取消后台调度，前台仍沿用每分钟的原有同步条件。任务在独立 Flutter isolate 中重新读取活动账号、密钥存储和该账号的自动同步偏好，再通过同一 API2 同步协调器上传本地修改、下载增量。前台同步、手动同步、附件上传和目录元数据操作共用 SQLite 过期运行锁，避免前后台引擎同时处理同一批修改；周期心跳续锁，异常退出后旧锁可过期恢复。离线插图待用户补交原件时任务结束，后续调度再试；暂时性网络失败交给 WorkManager 重试。

专项覆盖两个协调器的并发拒绝及旧锁过期恢复。完整 Flutter 测试 **756 项通过、2 项条件测试默认跳过**，静态检查无问题；Android debug APK 构建通过。按用户要求，不做真机或模拟机测试，系统后台实际执行与生命周期仍待设备验收。

## M04/M05 完整标题级别

核对旧富文本编辑器的 `toggleHeader` 后，补齐一级至六级标题与恢复正文菜单。Markdown 切换级别时替换已有 ATX 标记，重复选择当前级别取消标题；保持跨行选区边界，取消标题时处理末尾闭合井号并保留正文井号和光标位置。两种编辑器菜单均提供中文与英文。专项覆盖六个级别、混合选区、闭合标记、光标和菜单自动保存。

完整 Flutter 测试 **759 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。设备验证按用户要求暂缓。

## M04 Markdown Extra 定义列表与软换行

已核对旧 `markdownEditor/all.js` 的实际启用项：fenced_code_gfm、tables、def_list、attr_list、footnotes、strikethrough、newlines。当前 GFM 阅读器已覆盖围栏代码、表格、脚注解析与删除线，本批补齐定义列表和单换行保留。定义列表支持多个术语、多条释义、可选空行、缩进续行和嵌套段落/列表，使用现有原生块布局和同一组链接/账号图片回调；代码、标题、表格、引用定义和普通冒号不会误识别为术语。原笔记 Markdown 不做改写。

专项测试通过；脚注和属性列表已在后续批次补齐。

完整 Flutter 测试 **762 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。未进行真机或模拟机测试。

## M04 Markdown Extra 脚注、文内链接与属性列表

脚注引用和 `#fragment` 文内链接会在当前阅读位置上方打开原生内容窗口，展示脚注或目标标题及其所属小节；脚注返回链接关闭窗口。解析范围严格限制在当前笔记 AST，缺失或非法编码的锚点不会发起网络请求，普通 HTTP/HTTPS 链接仍走已有确认对话框。展开内容继续使用原有账号图片缓存、数学公式和链接处理器。

兼容旧 Markdown Extra 对 ATX/Setext 标题和围栏代码的 `{#id .class}` 属性列表语法。只接受旧版允许的 ID 和类名字符，不解释 CSS、事件属性或其它 HTML 属性；代码正文中的字面属性文本保持不变。专项覆盖多级标题小节、脚注内引用链接、非法锚点、代码与普通段落边界以及属性注入拒绝。

完整 Flutter 测试 **765 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。按用户要求未进行真机或模拟机测试。

## M05 正文图片缩放查看与功能边界复核

已按旧 Android `EditorFragment.onClickedImage` 核对富文本图片交互：旧端点击正文图片后打开图片查看页。本批为 Markdown、富文本安全阅读、编辑预览、共享和历史页共用的缓存图片组件增加全屏查看器，支持双指缩放和平移；只使用已经读取或明确下载到账号缓存的字节，不新增网络入口。关闭后回到原阅读位置，缺失或损坏图片仍显示原占位和手动下载操作。

同时逐项核对旧富文本工具栏：加粗、斜体、H1–H6、正文、引用、有序/无序列表、链接插入/移除和图片插入均已迁移，Flutter 端还支持撤销重做、下划线、删除线、颜色、字号、对齐和表格操作。旧移动端没有图片尺寸编辑或高级 CSS 布局工具，因此移除这两个没有旧功能依据的迁移缺口；复杂 HTML 继续通过无损源码模式编辑。设备上的 WebView 输入法、选区和撤销行为仍按用户要求暂缓验证。

正文缓存图片专项、完整 Flutter 测试 **765 项通过、2 项条件测试默认跳过**，静态检查无问题，Android debug APK 构建通过。按用户要求未进行真机或模拟机测试。

## 当前范围功能迁移完成审计

重新逐项对照旧 Android 行为、desktop API2 用法和 M01–M26 后，未再发现能由 Flutter/Android 客户端独立完成且尚未实现的功能。M07 笔记本删除受 B01 阻塞；M11 全局标签删除/重命名受 B02/B06 阻塞；M13 共享编辑与权限管理受 B03 阻塞；M12 完整历史资源恢复受 B07 阻塞。按用户要求这些服务端修改只记录，留待后续目标。

其余未闭环文字都是设备或跨客户端验收，以及明确暂缓的 iOS 原生和发布工作。当前最终证据为完整 Flutter 测试 **765 项通过、2 项条件测试默认跳过**、静态检查无问题、Android debug APK 构建通过；没有真机或模拟机测试证据。

## 服务端阻塞项闭环与共享只读

服务端现已修复笔记本同步删除、空标签清除、全局标签删除的 USN/笔记联动，以及历史版本的编辑器格式和文件清单元数据。共享权限统一为只读，服务端忽略旧客户端传入的可编辑权限并拒绝共享者写入；只有原作者能修改原文。移动端共享列表增加“复制到我的笔记本”，由服务端在确认共享读取权限后复制正文、图片和附件，再同步为当前账号的独立笔记。笔记更新通过 API2 的 `ClearTags` 明确清空标签，历史恢复同时恢复 Markdown/富文本格式；本地历史缓存 schema 升至 v21。

完整测试运行到 **765 项通过、2 项条件测试跳过**，唯一失败为新增文案尚未生成；生成并回归后，本地化、共享复制、历史缓存专项测试及静态分析全部通过。服务端与 desktop 的完整 Go 测试、Web 生产构建均通过。


## 2026-10-16 目录删除与标签管理收尾

- API2 接入 `/api2/client/notebook/delete` 和 `/api2/tag/deleteTag`。删除使用缓存 USN，检查业务响应，不把返回 USN 直接作为下载游标。笔记本删除通过同步 tombstone 收敛；响应丢失时保留缓存，下一次同步确认结果。
- 笔记本删除前在同步互斥区内重新检查本地版本、待同步修改、子笔记本和活动笔记。工作区提供确认与失败提示。
- 标签页增加删除/重命名菜单与中英文文案。重命名包含回收站笔记，事务替换并去重，保留标题、正文等字段；上传失败的替换保留在 dirty 队列，可重试。全部引用上传后再删除旧目录项。API2 没有原子重命名，该多请求流程不保证跨设备并发原子性。
- B07 重新核对：`app/service/AttachService.go` 的 `DeleteAttach` 删除附件数据库记录并执行 `os.Remove`；历史 Files 元数据不足以恢复原件。当前范围禁止改服务端，因此完整附件恢复未实现，不能将这项标为完成。后续服务端需保留被历史引用的文件、提供受授权的历史文件 API2 读取，并区分缺失清单与已知空清单；移动端再接入可恢复的附件集合提交。
- 本轮只修改 mobile-app，未修改服务端、desktop 或 legacy-android；未执行设备、iOS 或发布验收。
- 验证：完整 Flutter 测试 774 项通过、2 项跳过；专项新增覆盖删除响应丢失、非空/dirty 拒绝、活动/回收站标签联动、重命名失败重试及菜单确认/取消。


## 2026-10-16 三端历史附件恢复

用户明确授权服务端/Web、desktop、mobile 一并修复并各自提交。本轮接入 `/api2/note/restoreHistory`：按稳定 historyId 和当前 USN 请求原作者的完整快照恢复，拒绝 dirty 笔记和未处理上传；成功后正常同步更新正文、格式、附件集合。在线菜单仅对 FilesComplete=true 的版本显示“恢复正文和附件”；原有正文恢复保留，离线不调用完整恢复 API。

服务端保留删除附件的原件、恢复前版本和内部附件记录，提供完整清单标记；Web 与 desktop 同步接入。旧快照缺少完整标记或原件已经丢失时明确失败，不能将它们当作无附件版本。设备、iOS 原生和发布继续暂缓。本轮替代上一个记录中 B07 尚受阻的结论。

本批验证：Flutter 全量 **780 项通过、2 项跳过**，静态检查通过；服务端与 desktop 完整 Go 回归通过，Web 14 项测试和生产构建通过。未进行真机/模拟器、iOS 构建或发布。


## 2026-10-21 API2 Bearer 认证、共享复制与 PostgreSQL 历史修复

服务端所有受保护 API2 控制器统一从 Bearer token 建立当前用户上下文，旧客户端的查询参数 token 暂时兼容；Web 使用标签页会话存储 token，desktop 删除远程浏览器 Cookie 桥接，mobile 删除 `_accountFormAction` 临时 Cookie 登录流程。账号资料、头像、正文图片与附件上传均直接携带当前账号 token，密码修改和邮箱修改仍保留业务所需的旧密码确认。

共享原文在服务端权限入口统一为仅原作者可写，接收者通过复制接口生成归自己所有的新笔记后再编辑。PostgreSQL 更新编码器开始遵循字段标签，历史记录主键稳定映射为 `id`。服务端数据库/控制器/服务测试、Web 测试与生产构建、desktop API/webapi 测试及 mobile API2 专项测试均通过；真机、模拟器、iOS 与发布验证继续暂缓。
