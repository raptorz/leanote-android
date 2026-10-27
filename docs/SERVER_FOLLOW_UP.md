# 服务端整改结果与增强实现

更新日期：2026-10-27。

## 已完成的原阻塞项

此前记录的 API2 Cookie Session 混用与 PostgreSQL 历史字段映射问题已完成联合修复：

- API2 受保护路由统一接受 `Authorization: Bearer <token>`，身份通过请求上下文传入旧控制器；缺失或失效凭据返回 JSON `401/NOTLOGIN`，不再重定向登录页。
- Web、desktop、mobile 均发送 Bearer token。服务端暂时继续接受 `token` 参数，以兼容已发布的旧客户端。
- 共享原文统一只读，仅原作者可写；共享者只能复制到自己的笔记本后编辑。副本使用新 ID，并归复制者所有。
- PostgreSQL 结构体更新遵循 `db`/`bson` 字段标签，`NoteContentHistory.NoteId` 正确更新 `id`，不再生成不存在的 `note_id`。

API2 token 使用 `crypto/rand` 生成 32 字节随机数并以 Base64URL 编码，不是 JWT，也不是 MongoDB ObjectId。服务端保存可撤销会话，退出及密码修改会撤销对应凭据；移动端只通过 Bearer 请求头传输，不写入 URL。随机性单元测试和真实 API2 失效/退出测试均已加入。

## API2 1.1.0 增强

后续开发与验收以 PostgreSQL 为目标，未来将移除 MongoDB 运行后端。
本轮不再安排 MongoDB 测试，也未在本次直接移除现有支持代码。

服务端版本集中维护于 `app/version/version.go`，本轮从 1.0.0 升到 1.1.0；旧 `/api` 路由及创建行为不变，`min_version` 保持空。协议细节以[服务端 API2 文档](https://github.com/gemsnote/gemsnote/blob/main/docs/development/API2.md)为准。

1. **笔记本创建幂等**：`POST /api2/client/notebook/add` 接受 `clientNotebookId`，使用客户端持久保存的 24 位十六进制创建键作为服务端主键。重复请求返回同一笔记本，不覆盖已修改的标题/父级，不复活 tombstone，不泄露其他账号的同 ID 记录。数据库主键处理多进程竞争。Flutter 为 1.1.0 及以上服务端保存创建请求快照，响应丢失或进程重启后使用原键恢复；旧的不确定请求仍需人工确认，不猜测关联。
2. **图片上传回执与安全清理**：`POST /api2/file/pasteImage` 可传 `uploadId`；`GET /api2/file/imageUpload` 按该键或文件 ID 查询，返回归属笔记、内容摘要及状态；`POST /api2/file/cleanupImageUpload` 只清理当前用户的新式、从未被保存引用的上传。正文、封面、图片关系及历史写入前永久保留其原件，数据库原子转换与清理互斥；历史裁剪不重新开放清理。清理保留 tombstone，防止旧请求重新引用或重新上传同键。旧图片、头像和附件不属于此清理范围。

Flutter 的图片暂存菜单增加“查询并恢复上传结果”和“清理未引用的服务端图片”。恢复核对账号、笔记和 SHA-256，不重新上传；清理需显式确认，拒绝本地未同步正文引用，保留本地原件。自动后台扫描/删除历史资源不在范围内。

清理发送前先保存本地 `cleaning` 状态；响应丢失后禁止插入该文件，只能重试确认清理或保留/导出原件。当前完整 Flutter 805 项通过、10 项条件跳过；临时 PostgreSQL/API2 8 项通过，追加并发/权限及 PostgreSQL race detector 验证通过。

PostgreSQL 启动时执行 1.1.0 迁移，新增上传状态、目标笔记、摘要与唯一上传键；MongoDB 增加稀疏唯一上传键索引，无需回填，缺少状态的旧文档始终受保护。升级后不要混跑旧服务端进程，旧进程不会执行新上传的引用保护；回滚前须停止写入并采用对应数据库备份。

本文件不再包含尚待开发的服务端阻塞项。设备验证、iOS 与发布仍按总迁移计划暂缓。实际运行证据见 [API2_LIVE_TESTING.md](API2_LIVE_TESTING.md) 和根目录 [MIGRATION.md](../MIGRATION.md)。
