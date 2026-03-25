# SPEC-001: 系统音频采集 (System Audio Capture)

## 状态: 待实现 | 优先级: 中 | 里程碑: M5

---

## 1. 概述

通过 ScreenCaptureKit (macOS 13+) 采集系统音频输出，支持与麦克风混合录制，用于会议录音（捕获远程参会者声音）、播客收听记录等场景。

## 2. 目标

- 支持三种音频输入源：麦克风 / 系统音频 / 麦克风+系统音频
- 用户可在设置中切换音频源
- 系统音频采集需请求屏幕录制权限，在 UI 中明确提示
- 混合模式下两路音频合并为单声道 16kHz PCM，复用现有 ASR 管线

## 3. 技术方案

### 3.1 ScreenCaptureKit 采集

```swift
import ScreenCaptureKit

class SystemAudioCaptureService {
    private var stream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?

    func startCapture() async throws {
        let content = try await SCShareableContent.current
        let display = content.displays.first!

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true  // 不采集自身音频
        config.sampleRate = 16000
        config.channelCount = 1

        // 不采集视频，仅音频
        config.width = 1
        config.height = 1
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        stream = SCStream(filter: filter, configuration: config, delegate: nil)

        streamOutput = SystemAudioStreamOutput()
        try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: .global())
        try await stream?.startCapture()
    }

    func stopCapture() async {
        try? await stream?.stopCapture()
        stream = nil
    }
}
```

### 3.2 混合模式

```
麦克风 (AVAudioEngine inputNode)
    │
    ▼
MixerNode ──► Ring Buffer (ASR) + File Writer
    ▲
    │
系统音频 (SCStream audio output)
```

- 使用 `AVAudioMixerNode` 将两路音频混合
- 或在 `AudioCaptureService` 中手动混合 PCM buffer（采样率对齐后逐样本加权平均）
- 建议权重：麦克风 0.6 / 系统音频 0.4（可配置）

### 3.3 AudioSource 枚举扩展

```swift
enum AudioSource: String, Codable, CaseIterable {
    case microphone         // 仅麦克风（现有）
    case systemAudio        // 仅系统音频（新增）
    case mixed              // 麦克风 + 系统音频（新增）
}
```

### 3.4 权限处理

- 系统音频需要 **屏幕录制权限**（`NSScreenCaptureUsageDescription`）
- 首次选择系统音频源时弹出系统权限对话框
- 权限被拒绝时：显示引导用户到 系统设置 > 隐私与安全性 > 屏幕录制
- 沙盒兼容：ScreenCaptureKit 在沙盒内可用（无需额外 entitlement）

## 4. 影响范围

| 文件 | 变更 |
|------|------|
| `AudioCaptureService.swift` | 新增系统音频采集路径，混合模式 |
| `AudioConfig.swift` | 新增 `AudioSource` 枚举 |
| `SettingsView.swift` | 新增音频源选择器 |
| `RecordingViewModel.swift` | 传递音频源配置 |
| `notetaker.entitlements` | 无需新增（ScreenCaptureKit 不需要额外 entitlement） |
| `Info.plist` | 新增 `NSScreenCaptureUsageDescription` |

## 5. 测试计划

- [ ] 单独系统音频采集：播放音频 → 验证转录输出
- [ ] 混合模式：同时说话+播放音频 → 验证两路均被转录
- [ ] 权限拒绝：优雅降级，显示错误提示
- [ ] 热插拔：录音中切换音频源（不支持，需停止后重新开始）

## 6. 开放问题

1. `excludesCurrentProcessAudio` 在 macOS 13 可用，但 macOS 12 不支持 — 最低版本已是 macOS 26，无影响
2. 是否支持选择特定应用的音频（`SCContentFilter` 支持按应用过滤）— v1 先全局采集
