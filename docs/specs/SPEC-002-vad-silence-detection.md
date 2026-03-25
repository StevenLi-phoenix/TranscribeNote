# SPEC-002: VAD 静音检测 (Voice Activity Detection)

## 状态: 待实现 | 优先级: 高 | 里程碑: M5

---

## 1. 概述

在 ASR 管线中集成 VAD（语音活动检测），用于确认句子边界、跳过静音段以减少无效转录、在长时间静音时自动暂停/停止录音。

## 2. 目标

- 检测静音段，避免向 ASR 引擎喂入纯噪音
- 确认句子边界，提高 TranscriptSegment 的分段质量
- 支持可配置的静音超时：连续 N 秒静音后自动停止录音
- 低 CPU 开销（< 2% 额外负载）

## 3. 技术方案

### 3.1 基于能量阈值的简单 VAD

利用现有 `AudioCaptureService.onAudioLevel` 的 RMS 计算，无需引入外部库：

```swift
class SimpleVAD {
    var silenceThreshold: Float = 0.05    // 0..1 标准化能量
    var silenceDurationForPause: TimeInterval = 2.0   // 暂停 ASR 喂入
    var silenceDurationForStop: TimeInterval?          // nil = 不自动停止

    private var lastSpeechTime: Date = .now
    private(set) var isSpeaking: Bool = false

    func processAudioLevel(_ level: Float) -> VADEvent {
        if level > silenceThreshold {
            lastSpeechTime = .now
            if !isSpeaking {
                isSpeaking = true
                return .speechStarted
            }
            return .speech
        }

        let silenceDuration = Date.now.timeIntervalSince(lastSpeechTime)

        if isSpeaking && silenceDuration > silenceDurationForPause {
            isSpeaking = false
            return .speechEnded(silenceDuration: silenceDuration)
        }

        if let stopDuration = silenceDurationForStop,
           silenceDuration > stopDuration {
            return .silenceTimeout
        }

        return .silence
    }
}

enum VADEvent {
    case speech
    case speechStarted
    case speechEnded(silenceDuration: TimeInterval)
    case silence
    case silenceTimeout
}
```

### 3.2 集成点

```
AudioCaptureService (RMS level)
    │
    ▼
SimpleVAD.processAudioLevel()
    │
    ├── .speechStarted → 恢复向 ASR 喂入 buffer
    ├── .speechEnded   → 标记句子边界，暂停 ASR 喂入
    ├── .silenceTimeout → RecordingViewModel.stopRecording()
    └── .silence       → 跳过 ASR 喂入（省电）
```

### 3.3 可配置参数

在 `AppSettings` / `AudioConfig` 中新增：

```swift
var vadEnabled: Bool = true
var vadSilenceThreshold: Float = 0.05
var silenceTimeoutSeconds: Int? = 300    // spec 默认 5 分钟
```

## 4. 影响范围

| 文件 | 变更 |
|------|------|
| 新增 `Services/SimpleVAD.swift` | VAD 逻辑 |
| `AudioCaptureService.swift` | 在 audio level 回调中调用 VAD |
| `RecordingViewModel.swift` | 响应 `.silenceTimeout` 事件 |
| `SettingsView.swift` | VAD 开关、静音超时配置 |

## 5. 测试计划

- [ ] 单元测试：给定 RMS 序列 → 验证 VADEvent 输出
- [ ] 集成测试：静音 → 说话 → 静音 → 验证 ASR 仅处理有声段
- [ ] 静音超时：模拟 300s 静音 → 验证自动停止

## 6. 未来增强

- 集成 WebRTC VAD 或 Silero VAD 获得更精确的语音检测
- 基于 VAD 的说话人切换检测（辅助 diarization）
