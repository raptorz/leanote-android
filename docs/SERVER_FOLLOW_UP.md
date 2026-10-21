# 服务端待处理清单

更新日期：2026-10-21。

此前记录的 API2 Cookie Session 混用与 PostgreSQL 历史字段映射问题已完成联合修复：

- API2 受保护路由统一接受 `Authorization: Bearer <token>`，身份通过请求上下文传入旧控制器；缺失或失效凭据返回 JSON `401/NOTLOGIN`，不再重定向登录页。
- Web、desktop、mobile 均发送 Bearer token。服务端暂时继续接受 `token` 参数，以兼容已发布的旧客户端。
- 共享原文统一只读，仅原作者可写；共享者只能复制到自己的笔记本后编辑。副本使用新 ID，并归复制者所有。
- PostgreSQL 结构体更新遵循 `db`/`bson` 字段标签，`NoteContentHistory.NoteId` 正确更新 `id`，不再生成不存在的 `note_id`。

API2 token 不要求采用 JWT 格式，但必须是不可预测、具有足够熵的安全随机值，并保持服务端撤销能力。当前 Bearer 传输和服务端会话撤销合同已经统一；后续联调同时检查 token 不出现在 URL、日志和错误信息中。若服务端仍使用可推测的标识符生成 token，应改为密码学安全随机数，并补充失效、退出和密码变更撤销测试。

本文件不再包含尚待开发的服务端阻塞项。设备验证、iOS 与发布仍按总迁移计划暂缓。
