# Known Bugs

## ~~BUG-001: API Key 明文存储在 UserDefaults~~ [RESOLVED]

**严重度**: High (App Store 审核阻塞)

`LLMConfig.apiKey` 以明文 JSON 存储在 UserDefaults (`liveLLMConfigJSON`, `overallLLMConfigJSON`)。任何有磁盘访问权限的进程都能读取。

**修复方案**: 迁移到 Keychain (`Security.framework`)，UserDefaults 中仅保留非敏感配置字段。

**Status**: ✅ Resolved — Implemented `KeychainService` for secure API key storage; `LLMConfig.apiKey` now excluded from JSON encoding (via custom `CodingKeys`); automatic one-time migration from UserDefaults to Keychain via `KeychainMigration.migrateIfNeeded()`; all tests pass.

## ~~BUG-002: 崩溃日志使用自定义 signal handler~~ [RESOLVED]

**严重度**: Medium

`CrashLogService` 使用 POSIX `signal()` 安装自定义信号处理器，写入 `last_crash.log`。

**问题**:
- 可能与系统崩溃报告 / 第三方 crash reporter 冲突
- App Store 审核可能质疑自定义信号处理的必要性
- `signal()` 在多线程环境下行为未定义（应使用 `sigaction()`）

**修复方案**: 迁移到 `MetricKit` (`MXCrashDiagnostic`) 或集成 Sentry/Crashlytics 等标准 crash reporting SDK。

**Status**: ✅ Resolved — Replaced POSIX signal handlers with MetricKit (`MXMetricManagerSubscriber`); `CrashLogService` now receives crash diagnostics via `didReceive(_: [MXDiagnosticPayload])` on next launch after crash; extracts termination reason, exception type/code, signal, VM region info, and call stack tree JSON; all tests pass.
