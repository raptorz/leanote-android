# 移动端开发

## 环境

- Flutter stable 3.47 或更高版本
- Android SDK（最低系统版本跟随当前 Flutter stable）
- Android Studio 或支持 Flutter 的编辑器
- iOS 构建需要 macOS、Xcode 和 CocoaPods

中国大陆网络可使用：

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

## 常用命令

```sh
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

iOS 工程只能在 macOS 上构建：

```sh
flutter build ios
```

## 服务端要求

客户端要求 Gemsnote API2 v1.0.0。登录接口 `/api2/auth/login` 一次返回 token、用户资料和服务端版本；旧 `/api` 与旧 Leanote 服务端不在支持范围内。

首次登录按 USN 分页下载笔记本、含正文笔记和标签，并在单个 SQLite 事务中替换该账号快照。token 只在完整快照成功落库后写入系统安全存储，避免残缺缓存被当成有效登录。

## 应用图标

高分辨率源图为 `assets/branding/gemsnote.png`，来自项目提供的透明背景 Gemsnote 图标。
该目录仅用于构建维护，不作为 Flutter 运行时资源打包；页面仍使用 `assets/images/gemsnote_s.png`。
安装 ImageMagick（Ubuntu/Debian：`sudo apt install imagemagick`；macOS：`brew install imagemagick`）后运行：

```sh
bash scripts/generate_icons.sh --help
bash scripts/generate_icons.sh
flutter test test/launcher_icons_test.dart
```

脚本可从任意工作目录调用，支持 ImageMagick 6 的 `convert` 和 7 的 `magick`，
不下载外部资源，只覆盖 Flutter Android/iOS 的图标 PNG，不修改 `legacy-android/`。
生成物提交到 Git，因此普通构建无需安装 ImageMagick。

Android 提供五档密度的传统图标和前景图，以及 API 26+ 自适应图标 XML。
前景置于 108dp 画布的中央 46dp 方形内，保证完整主体位于 66dp 安全圆内，
背景使用 `#193b35`；参见 [Android 自适应图标规范](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)。
iOS 保留现有 asset catalog 的全部尺寸及 1024px 图标，输出无透明通道 RGB PNG，
不预先裁圆角；参见 [Apple AppIcon 资源目录说明](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)。
当前未提供 Android 主题单色层或新的 iOS 分层外观。
更新图标后需要重新构建/安装应用，不会通过 Flutter 热重载替换桌面图标；
iOS 编译仍需 macOS/Xcode，桌面遮罩及安装后的显示需真机验证。

## 同步模式

- 立即同步：先上传本地 dirty 笔记，再从上次账号 USN 拉取增量。
- 完全同步（合并）：同样先上传，然后从 USN 0 下载所有类型，使用同一个事务合并流程；用于补回遗漏的旧记录，不清空本地数据。
- 重新同步：确认后不上传本地修改，下载成功才原子替换账号快照；下载失败保留原缓存。

完全同步由 `SyncCoordinator.synchronizeFull` 实现，不新增或修改 API2 接口。
与增量同步使用相同的固定检查点、分页和 dirty 防覆盖逻辑；服务端 USN 倒退仍拒绝合并。
未出现在快照中的本地记录不会自动删除或重传，明确的远程删除标记仍生效。
正文冲突继续报错保留本地，尚不生成副本。完全同步替换命中的笔记行时，
其关联文件缓存沿用既有合并清理规则；不保证所有文件缓存保留。

## Markdown 阅读

Markdown 阅读使用 [flutter_markdown_plus](https://pub.dev/packages/flutter_markdown_plus)
原生组件，并保留可复制的原文模式。个人笔记图片由账号隔离的缓存组件处理；
未缓存时由用户手动点击、经 API2 校验后下载，不启用渲染器默认的网络/本地文件加载。
共享、历史及编辑预览中的图片仍为占位。链接仅展示地址并允许用户复制。
此实现不支持 Markdown 中内嵌 HTML 的浏览器渲染。

## 富文本阅读

个人笔记默认与共享、历史一样使用 `SafeHtmlNoteBody` 原生安全预览，不使用 WebView
自动读取正文资源。保留基本排版、原文查看/复制/导出，不执行脚本、CSS、嵌入页面或链接。
复杂布局和表格样式降级，不写回转换结果；HTML 可视化编辑仍待实现。
个人笔记额外接入现有账号隔离图片缓存：正文下方集中显示前 100 张 `img` 图片，
正文位置保留文字标记，不还原内联排版。缓存缺失时仅对合法同源 API2 文件引用提供手动下载。
图片集合跳过脚本、iframe 等被省略内容，不使用 `srcset`、CSS 图片或外部资源自动加载。
返回文件页后更新缓存显示；共享、历史及编辑预览不传入下载能力，仍显示占位。

## 原文导出

`NoteExporter` 调用已锁定依赖版本的 `FilePicker.saveFile`，使用返回的 URI 判断
是否保存，取消返回 null；不把 Android content URI 当作本地路径写文件。
测试可注入保存回调验证字节、文件名、取消和失败行为。导出不执行 HTML，也不下载附件。
iOS 保存对话框只能在 macOS/iOS 环境完成构建和真机验收。

图片预览通过 `ImageExporter` 复用系统文件保存能力和文件名清理逻辑，只保存已读取的
图片字节，不再请求服务器。输出扩展名和 MIME 由 PNG/JPEG/GIF/WebP 文件头确定，
不信任服务端文件名或类型；仍限制每张最多 8 MiB。该检查只识别格式，图片解码验证
由读取图片的仓储层负责。导出到系统文件后不再受账号缓存清理控制，用户自行管理。

## 附件保存

普通附件通过 `/api2/note/getNote` 校验个人笔记归属与文件成员后，调用
`/api2/file/getAttach`，不使用正文 URL。该接口错误也可能返回 HTTP 200，
因此必须同时检查 `Content-Disposition: attachment`，不能把 JSON/登录页当附件保存。
下载不跟随重定向，响应头限时 30 秒、响应体总限时 60 秒，大小上限 32 MiB；
完整下载到内存后才打开系统保存窗口，空附件允许保存。文件名来自已校验的列表并清理路径字符，
忽略响应头文件名；原始字节不执行、不自动打开。下载后通过文件快照代号校验写入
现有 `note_files` 表，图片和附件共用 64 MiB 全账号字节限额，无需变更 schema。
取消保存仍保留缓存；显式离线保存不调用 API，空字节与未缓存的 NULL 区分。
刷新列表、权限撤销、删除与重新同步清理沿用图片策略，普通网络失败保留缓存但不自动回退。

## 测试原则

标签页面与编辑候选复用 `tagChoices` 的稳定排序/过滤。数据来自当前账号 SQLite
笔记的引用计数，不从标签同步表推断有哪些标签，不发起网络请求；每次打开页面/对话框
重新读取。标签页空查询显示前 10 个，非空查询搜索全部；编辑候选排除已选标签，
最多 20 个并可继续输入缩小范围。小屏使用有高度限制、可滚动的候选标签块，
不照搬桌面浮动列表。已有标签全部清空的服务端合同限制不变。

系统分享使用锁定的 `share_plus` 版本及 `SharePlus.instance.share(ShareParams(...))`，
仅传个人笔记标题、正文纯文本与当前菜单按钮位置（iPad popover 必需），不共享附件或凭据。
文本 UTF-8 上限 256 KiB，避免 Android 大文本 Intent 超限；不截断，超限改用导出原文。
原生结果只是面板交互结果，不是发送成功回执，因此不显示“分享成功”。测试注入分享回调，
验证载荷、取消/未知结果、失败及防重复操作；实际 Android/iOS 分享面板需真机验收。

`NotebookTargetPicker` 是笔记与笔记本移动的共用目标选择组件，复用 `NotebookTree`
的展示树；搜索只过滤显示并保留祖先，不重写层级或 ID。`canSelect` 控制合法目标，
笔记本移动继续使用 `canMoveNotebook` 检查原始父级链，不能只依赖展示树防止循环。
展开操作不触发选择，搜索不更改展开状态；无选中目标时不能提交。

- API 客户端测试必须检查 HTTP 方法、路径和 JSON 请求体
- SQLite 测试使用内存数据库，不依赖真实用户数据
- 同步测试需要覆盖分页、超时、原子提交、ID 映射和账号隔离
- 提交前至少运行 `flutter analyze` 和 `flutter test`
