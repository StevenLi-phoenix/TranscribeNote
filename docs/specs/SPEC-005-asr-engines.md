# SPEC-005: 备选 ASR 引擎 (Additional ASR Engines)

## 状态: 不修复 (whisper.cpp) / 待实现 (云端 API) | 优先级: 低 | 里程碑: M5

---

## 1. 概述

当前 ASR 仅有 Apple Speech (SpeechAnalyzer, macOS 26+) 实现。原 spec 规划了 4 种引擎：

| 引擎 | 状态 | 说明 |
|------|------|------|
| Apple Speech | ✅ 已实现 | `SpeechAnalyzerEngine` — 低延迟，原生集成 |
| whisper.cpp | ❌ **不修复** | 本地部署复杂，模型文件 ~500MB，Apple Speech 已满足需求 |
| Deepgram API | 🔲 待实现 | 流式 WebSocket API，高精度，支持说话人分离 |
| OpenAI Whisper API | 🔲 待实现 | REST API，最高精度，非流式 |

### 1.1 不修复 whisper.cpp 的原因

- Apple Speech (macOS 26+) 原生支持离线识别，延迟 < 1s，精度足够
- whisper.cpp 集成需要：编译 C++ 库、分发模型文件 (~500MB)、手动管理内存、无原生 Swift API
- SwiftWhisper 维护状态不确定
- 投入产出比不合理

## 2. Deepgram 流式 API

### 2.1 特性

- WebSocket 流式传输，延迟 ~300ms
- 支持说话人分离（diarization）
- 支持多语言
- 需要 API Key + 网络连接

### 2.2 实现方案

```swift
nonisolated final class DeepgramEngine: ASREngine, @unchecked Sendable {
    private var webSocket: URLSessionWebSocketTask?
    private let apiKey: String

    func startRecognition(config: ASRConfig) {
        let url = URL(string: "wss://api.deepgram.com/v1/listen?model=nova-2&language=\(config.language)")!
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        webSocket = URLSession.shared.webSocketTask(with: request)
        webSocket?.resume()
        receiveLoop()
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // PCM → 16-bit LE raw bytes → send as .data message
        let data = buffer.toRawPCMData()
        webSocket?.send(.data(data)) { _ in }
    }

    func stopRecognition() async {
        webSocket?.cancel(with: .normalClosure, reason: nil)
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard case .success(.string(let json)) = result else { return }
            // Parse Deepgram JSON response → TranscriptResult
            // Call onResult callback
            self?.receiveLoop()
        }
    }
}
```

### 2.3 配置

```swift
extension ASRConfig {
    var deepgramAPIKey: String? // 存储在 Keychain
    var deepgramModel: String   // "nova-2" (default)
}
```

## 3. OpenAI Whisper API

### 3.1 特性

- REST API，非流式（批量处理）
- 最高精度
- 适合后处理（录音结束后重新转录以获得更高精度）

### 3.2 实现方案

```swift
nonisolated final class OpenAIWhisperEngine: ASREngine, @unchecked Sendable {
    // 非流式：累积音频 buffer，定期（每 10-15s）发送一批
    private var accumulatedBuffers: [AVAudioPCMBuffer] = []
    private var batchTimer: Timer?

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        accumulatedBuffers.append(buffer)
    }

    private func processBatch() async throws {
        let audioData = mergeBuffersToWAV(accumulatedBuffers)
        accumulatedBuffers.removeAll()

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // multipart/form-data with audio file
        let (data, _) = try await URLSession.shared.upload(for: request, from: body)
        // Parse response → TranscriptResult
    }
}
```

## 4. ASR 引擎选择 UI

在 Settings 中新增 ASR 设置：

```
ASR 引擎: [Apple Speech ▾]
├── Apple Speech — 离线，低延迟，免费
├── Deepgram — 云端，高精度，支持说话人分离
└── OpenAI Whisper — 云端，最高精度

API Key: [••••••••] (仅云端引擎显示)
语言: [自动检测 ▾]
```

## 5. 影响范围

| 文件 | 变更 |
|------|------|
| 新增 `Services/DeepgramEngine.swift` | Deepgram WebSocket ASR |
| 新增 `Services/OpenAIWhisperEngine.swift` | OpenAI Whisper REST ASR |
| `ASREngine.swift` | 无变更（协议已足够通用） |
| `SettingsView.swift` | 新增 ASR 引擎选择 tab |
| `RecordingViewModel.swift` | 根据设置创建对应引擎 |

## 6. 测试计划

- [ ] Deepgram：Mock WebSocket → 验证流式解析
- [ ] OpenAI Whisper：Mock HTTP → 验证批量处理
- [ ] 引擎切换：Apple Speech ↔ Deepgram → 验证无状态残留
- [ ] 网络断开：云端引擎优雅降级提示

## 7. 不做

- whisper.cpp 本地集成（已决定不修复）
- 说话人分离 UI（等 Deepgram 引擎实现后再设计）
