# TODO

## TODO-001: SwiftData Schema 版本迁移计划

**优先级**: Low (上架前需完成)

当前无 schema 迁移策略。一旦上架后修改数据模型（增删字段、改类型），需要显式的 `SchemaMigrationPlan` 防止用户数据丢失。

**需要**:
- 定义 `VersionedSchema` 快照
- 编写 `SchemaMigrationPlan` 处理 v1 → v2 迁移
- 非 additive 变更需要 `MigrationStage.custom` 手写迁移逻辑

## TODO-002: App Store 隐私合规（网络请求 & 数据传输）

**优先级**: High (上架必须)

App 会将用户转录文本发送到外部 LLM API（OpenAI、Anthropic、或任意自定义端点）进行摘要生成。App Store 审核对此有明确要求：

**需要**:
- **隐私政策 URL**: App Store Connect 提交时必填，需说明收集/传输了哪些数据、传给谁、目的是什么
- **App Privacy Nutrition Labels**: 在 App Store Connect 声明数据用途类别（"User Content" → "Third-Party Advertising/Analytics" 等）
- **应用内隐私披露**: 首次配置外部 LLM API 时，向用户说明转录文本将发送到第三方服务器
- **App Review 说明**: 审核备注中解释网络请求用途（"用户主动配置的 LLM API 用于文本摘要，不自动上传任何数据"）

**涉及的数据传输**:
- 转录文本（TranscriptSegment.text）→ LLM API
- 可选的上下文摘要（前文 SummaryBlock.content）→ LLM API
- API Key（用户自行配置，app 不收集）
