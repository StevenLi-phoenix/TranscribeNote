# SPEC-004: 应用级设置补全 (App-wide Settings)

## 状态: 待实现 | 优先级: 高 | 里程碑: M4

---

## 1. 概述

补全 spec 中定义但尚未实现的应用级设置项：开机启动、音频质量、最大录音时长、静音超时、存储路径、自动清理、导出格式偏好。

全局快捷键暂不实现（需引入 KeyboardShortcuts 库）。

## 2. 设置项清单

### 2.1 通用设置 (General Tab)

| 设置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| 开机启动 | Bool | false | 使用 `SMAppService.mainApp` (macOS 13+) |
| 菜单栏显示 | Bool | true | 控制 MenuBarExtra 可见性 |
| Dock 图标 | Bool | true | `NSApp.setActivationPolicy()` |

### 2.2 录音设置 (Recording Tab)

| 设置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| 音频质量 | Enum | standard | standard(16kHz) / high(44.1kHz) |
| 最大录音时长 | Int? | nil | 分钟，nil=无限制 |
| 静音超时 | Int? | 300 | 秒，nil=不自动停止（依赖 SPEC-002 VAD） |

### 2.3 存储设置 (Storage Tab)

| 设置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| 音频存储路径 | String | ~/Documents/LiveScribe/ | 通过 NSOpenPanel 选择 |
| 保留天数 | Int | 30 | 超期自动删除音频文件 |
| 默认导出格式 | ExportFormat | .markdown | 导出时的默认格式 |

## 3. 技术方案

### 3.1 开机启动

```swift
import ServiceManagement

struct LaunchAtLoginToggle: View {
    @AppStorage("launchAtLogin") var launchAtLogin = false

    var body: some View {
        Toggle("开机时自动启动", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    Logger.app.error("Launch at login toggle failed: \(error)")
                    launchAtLogin = !newValue  // revert
                }
            }
    }
}
```

### 3.2 Dock 图标控制

```swift
@AppStorage("showInDock") var showInDock = true

func updateDockVisibility() {
    NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
}
```

### 3.3 音频质量

扩展 `AudioConfig`：

```swift
enum AudioQuality: String, Codable, CaseIterable {
    case standard   // 16kHz mono — 适合 ASR
    case high       // 44.1kHz mono — 高保真存档
}

// 在 AudioCaptureService 中根据 quality 设置采样率
```

### 3.4 自动清理

```swift
struct StorageCleanupService {
    static func cleanupOldRecordings(retentionDays: Int) {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -retentionDays, to: .now
        )!
        let recordingsDir = AudioCaptureService.recordingsDirectory()
        // 遍历文件，删除 modificationDate < cutoff 的音频文件
        // 注意：不删除 SwiftData 中的 session 记录，仅清理音频文件
        // session.audioFilePath 失效时 UI 显示 "音频文件已清理"
    }
}
```

- 在 `notetakerApp.init()` 中触发，每次启动检查一次
- 或使用后台 Task 定期检查

## 4. Settings UI 结构

```
Settings (Window)
├── General Tab          ← 新增
│   ├── 开机启动
│   ├── 菜单栏显示
│   └── Dock 图标
├── Recording Tab        ← 新增
│   ├── 音频质量
│   ├── 最大录音时长
│   └── 静音超时
├── Storage Tab          ← 新增
│   ├── 存储路径
│   ├── 保留天数
│   └── 默认导出格式
├── Models Tab           (现有)
├── LLM Tab              (现有)
└── Summarization Tab    (现有)
```

## 5. 影响范围

| 文件 | 变更 |
|------|------|
| `SettingsView.swift` | 新增 General / Recording / Storage tabs |
| `AudioConfig.swift` | 新增 `AudioQuality` 枚举 |
| `AudioCaptureService.swift` | 根据 quality 配置采样率 |
| `RecordingViewModel.swift` | 最大时长计时器 |
| 新增 `Services/StorageCleanupService.swift` | 自动清理逻辑 |
| `notetakerApp.swift` | 启动时触发清理 |

## 6. 测试计划

- [ ] 开机启动：toggle on/off → 验证 SMAppService 注册状态
- [ ] 音频质量切换：standard vs high → 验证输出采样率
- [ ] 最大时长：设为 1 分钟 → 验证自动停止
- [ ] 自动清理：创建过期文件 → 验证被删除
- [ ] 存储路径：选择自定义路径 → 新录音写入该路径

## 7. 不做

- 全局快捷键：需引入 `KeyboardShortcuts` 库，推迟
- PIN/Touch ID 解锁：App Store 审核前再考虑
