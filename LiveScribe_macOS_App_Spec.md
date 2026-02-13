# LiveScribe — macOS 定时录音实时转录 & LLM 摘要 App

## Product Spec v1.0

---

## 1. 概述

LiveScribe 是一款 macOS 原生应用，支持**定时开启录音**，对音频进行**实时 ASR（自动语音识别）转录**，并按可配置的时间间隔（默认 5 分钟）调用 **LLM 生成阶段性摘要**。适用于会议记录、课堂笔记、播客收听等场景。

### 1.1 核心价值

- **无感录音**：定时自动开始，无需手动操作
- **实时转录**：边录边转，延迟 < 2 秒
- **智能摘要**：周期性 LLM 总结，随时掌握关键信息
- **隐私优先**：支持本地 ASR 模型（Whisper），LLM 可选本地/云端

---

## 2. 目标平台 & 技术栈

| 层级 | 选型 | 说明 |
|------|------|------|
| UI 框架 | **SwiftUI** | macOS 13+ (Ventura) |
| 音频采集 | **AVFoundation / AVAudioEngine** | 系统麦克风 + 系统音频(可选) |
| ASR 引擎 | **whisper.cpp** (本地) / Apple Speech Framework / Deepgram API (云端) | 可切换 |
| LLM 引擎 | **llama.cpp** (本地 Ollama) / OpenAI API / Claude API | 可切换 |
| 数据持久化 | **SwiftData** (Core Data) + 文件系统 | 转录文本 + 音频文件 |
| 调度 | **Foundation Timer** + **UserNotifications** | 定时任务 |

---

## 3. 功能模块

### 3.1 定时录音调度器 (Scheduler)

```
┌─────────────────────────────────────┐
│         Scheduler Config            │
├─────────────────────────────────────┤
│ • 开始时间:  [日期时间选择器]         │
│ • 持续时长:  [__] 分钟 / 无限制      │
│ • 重复规则:  每天 / 工作日 / 自定义   │
│ • 提前提醒:  录音开始前 [1] 分钟通知  │
└─────────────────────────────────────┘
```

**行为定义：**

- 支持一次性定时和重复定时（类似闹钟）
- 到达指定时间后自动开始录音，菜单栏图标变红闪烁
- 支持「立即开始」快捷操作
- App 未运行时通过 `launchd` 或 Login Item 唤醒
- 录音开始/结束发送系统通知

### 3.2 音频采集模块 (Audio Capture)

**输入源：**

| 源 | 实现方式 | 权限 |
|----|---------|------|
| 麦克风 | `AVAudioEngine.inputNode` | 麦克风权限 (`NSMicrophoneUsageDescription`) |
| 系统音频 | `ScreenCaptureKit` (macOS 13+) | 屏幕录制权限 |
| 麦克风 + 系统音频 | 双路混合 | 两者都需要 |

**音频格式：**

```swift
struct AudioConfig {
    var sampleRate: Double = 16000      // Whisper 推荐
    var channels: Int = 1               // 单声道
    var bitDepth: Int = 16              // 16-bit PCM
    var bufferSize: Int = 4096          // ~256ms @ 16kHz
    var fileFormat: AudioFileFormat = .wav  // 存档格式，可选 .m4a
}
```

**流式处理管线：**

```
Mic/System Audio
    │
    ▼
AVAudioEngine (PCM Buffer)
    │
    ├──► Ring Buffer (ASR 用，滑动窗口 30s)
    │
    └──► File Writer (WAV/M4A 存档)
```

### 3.3 实时 ASR 转录模块 (Transcription)

**架构：**

```
Audio Ring Buffer (30s sliding window)
    │
    ▼
ASR Worker Thread (每 ~2-3s 触发一次)
    │
    ├──► 增量转录结果 (partial)
    │         │
    │         ▼
    │    TranscriptStore (append-only)
    │         │
    │         ▼
    │    UI 实时显示（滚动文本）
    │
    └──► VAD (Voice Activity Detection)
              │
              ▼
         静音检测 → 确认句子边界
```

**ASR 引擎抽象层：**

```swift
protocol ASREngine {
    var isStreaming: Bool { get }
    
    func configure(_ config: ASRConfig) async throws
    func startStreaming() async throws
    func feedAudio(_ buffer: AVAudioPCMBuffer) async
    func stopStreaming() async -> FinalTranscript
    
    var onPartialResult: ((PartialTranscript) -> Void)? { get set }
    var onFinalSegment: ((TranscriptSegment) -> Void)? { get set }
}

struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    let startTime: TimeInterval      // 相对录音开始
    let endTime: TimeInterval
    let text: String
    let confidence: Float
    let language: String?
    let speakerLabel: String?         // 说话人标识（如支持）
}
```

**引擎实现：**

| 引擎 | 延迟 | 精度 | 离线 | 说话人分离 |
|------|------|------|------|-----------|
| whisper.cpp (tiny/base/small) | ~1-3s | ★★★ | ✅ | ❌ (需额外模型) |
| Apple Speech | ~0.5s | ★★ | ✅ (macOS 14+) | ❌ |
| Deepgram Streaming API | ~0.3s | ★★★★ | ❌ | ✅ |
| OpenAI Whisper API | ~2-5s | ★★★★★ | ❌ | ❌ |

**默认推荐：** whisper.cpp `small` 模型（平衡速度和精度，完全离线）

### 3.4 LLM 摘要模块 (Summarizer)

**触发机制：**

```
TranscriptStore
    │
    ▼
Summarizer Timer (每 N 分钟触发)
    │
    ├──► 收集最近 N 分钟的 TranscriptSegments
    │
    ├──► 构建 Prompt（含上一次摘要作为上下文）
    │
    ├──► 调用 LLM
    │
    └──► 生成 SummaryBlock → 写入 SummaryStore
```

**可配置参数：**

```swift
struct SummarizerConfig: Codable {
    var intervalMinutes: Int = 5              // 摘要间隔（1-60 分钟）
    var minTranscriptLength: Int = 100        // 最少字符数才触发摘要
    var summaryLanguage: String = "auto"      // auto / zh / en / ...
    var summaryStyle: SummaryStyle = .bullets  // bullets / paragraph / actionItems
    var includeContext: Bool = true            // 是否包含上次摘要作为上下文
    var maxContextTokens: Int = 2000          // 上下文最大 token 数
    var customPrompt: String? = nil           // 用户自定义 prompt
}

enum SummaryStyle: String, Codable, CaseIterable {
    case bullets      // 要点列表
    case paragraph    // 段落摘要
    case actionItems  // 行动项提取
    case cornell      // 康奈尔笔记法
    case custom       // 自定义 prompt
}
```

**Prompt 模板（默认）：**

```
You are a meeting/lecture note assistant. Summarize the following transcript 
segment concisely. 

## Previous Summary Context
{previous_summary_or_"This is the beginning of the session."}

## New Transcript (last {N} minutes)
{transcript_text}

## Instructions
- Language: {output_language}
- Style: {summary_style}
- Highlight key decisions, action items, and important facts
- If speakers are identified, attribute statements to speakers
- Keep the summary under 200 words
```

**LLM 引擎抽象层：**

```swift
protocol LLMEngine {
    func summarize(prompt: String, config: LLMConfig) async throws -> String
    func isAvailable() async -> Bool
    var estimatedTokensPerSecond: Double { get }
}

struct LLMConfig: Codable {
    var provider: LLMProvider = .ollama
    var model: String = "llama3.2:3b"    // 或 "gpt-4o-mini", "claude-sonnet-4-20250514"
    var apiKey: String? = nil
    var baseURL: String? = nil            // Ollama: http://localhost:11434
    var temperature: Double = 0.3
    var maxTokens: Int = 512
}

enum LLMProvider: String, Codable, CaseIterable {
    case ollama         // 本地 Ollama
    case openai         // OpenAI API
    case anthropic      // Claude API
    case custom         // 兼容 OpenAI 格式的自定义端点
}
```

### 3.5 数据模型

```swift
// 一次录音会话
struct RecordingSession: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var title: String                    // 自动生成或用户编辑
    var audioFilePath: String
    var transcriptSegments: [TranscriptSegment]
    var summaries: [SummaryBlock]
    var totalDuration: TimeInterval
    var tags: [String]
}

// 单条摘要
struct SummaryBlock: Identifiable, Codable {
    let id: UUID
    let generatedAt: Date
    let coveringFrom: TimeInterval       // 覆盖的转录时间范围
    let coveringTo: TimeInterval
    let content: String
    let style: SummaryStyle
    let model: String                    // 生成模型标识
    var isPinned: Bool = false
    var userEdited: String? = nil        // 用户修改后的版本
}
```

---

## 4. UI 设计

### 4.1 应用结构

```
┌─ Menu Bar App (常驻菜单栏) ─────────────────┐
│  🔴 Recording... 00:23:45                    │
│  ├─ Pause / Stop                             │
│  ├─ Current Summary: "讨论了Q2预算分配..."     │
│  ├─ Open Main Window                         │
│  └─ Preferences...                           │
└──────────────────────────────────────────────┘

┌─ Main Window ────────────────────────────────┐
│ ┌─Sidebar──┐ ┌─Content Area────────────────┐ │
│ │ Sessions │ │  ┌─Transcript─┐ ┌─Summary─┐ │ │
│ │          │ │  │ 实时滚动    │ │ 摘要卡片 │ │ │
│ │ 📅 Today │ │  │ 转录文本    │ │ 时间线   │ │ │
│ │  └ 会议1  │ │  │            │ │         │ │ │
│ │  └ 课堂2  │ │  │ [带时间戳]  │ │ [可编辑] │ │ │
│ │ 📅 Yest. │ │  │            │ │         │ │ │
│ │          │ │  └────────────┘ └─────────┘ │ │
│ └──────────┘ └─────────────────────────────┘ │
│ ┌─Toolbar──────────────────────────────────┐ │
│ │ [▶ Start] [⏱ Schedule] [📤 Export] [⚙]  │ │
│ └──────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

### 4.2 关键界面

**实时转录视图：**
- 自动滚动跟随，可暂停滚动查看历史
- 时间戳标注（点击跳转音频位置）
- 高置信度文本正常显示，低置信度文本灰色/斜体
- 当前正在识别的文本用虚线下划线标注

**摘要时间线：**
- 每个摘要块显示为卡片，按时间排列
- 卡片显示：时间范围、摘要内容、模型标识
- 支持展开/折叠、编辑、固定、删除
- 点击摘要卡片高亮对应的转录文本段

**调度面板：**
- 日历视图展示已排定的录音计划
- 拖拽调整时间
- 快捷模板（每日站会、周例会等）

### 4.3 菜单栏交互

```
正常状态:    🎙 (灰色)
录音中:      🔴 (红色，可选脉冲动画)
已定时:      🎙⏰ (带小时钟角标)
处理中:      🎙⚙ (LLM 正在生成摘要)
```

---

## 5. 系统架构

```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Layer                        │
│  MenuBarView │ MainWindowView │ PreferencesView         │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────┴─────────────────────────────────┐
│                  ViewModel Layer                        │
│  RecordingVM │ TranscriptVM │ SummaryVM │ SchedulerVM   │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────┴─────────────────────────────────┐
│                  Service Layer                          │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │ AudioService │  │  ASRService  │  │ LLMService    │ │
│  │              │  │              │  │               │ │
│  │ • capture    │  │ • whisper    │  │ • ollama      │ │
│  │ • record     │──│ • apple      │  │ • openai      │ │
│  │ • playback   │  │ • deepgram   │  │ • anthropic   │ │
│  └──────────────┘  └──────┬───────┘  └───────┬───────┘ │
│                           │                  │         │
│  ┌──────────────┐  ┌──────┴───────┐  ┌───────┴───────┐ │
│  │ Scheduler    │  │ Transcript   │  │ Summarizer    │ │
│  │ Service      │  │ Store        │──│ Service       │ │
│  └──────────────┘  └──────────────┘  └───────────────┘ │
│                                                         │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────┴─────────────────────────────────┐
│                 Persistence Layer                        │
│  SwiftData (Sessions, Transcripts, Summaries)           │
│  FileManager (Audio files, Model files)                 │
└─────────────────────────────────────────────────────────┘
```

---

## 6. 关键流程

### 6.1 定时录音 + 转录 + 摘要 完整流程

```
[定时器触发]
    │
    ▼
AudioService.startCapture()
    │
    ├──► 创建 RecordingSession
    ├──► 开始写入音频文件
    ├──► 启动 ASR 流式引擎
    │       │
    │       ├──► 每 2-3s 产出 TranscriptSegment
    │       │       │
    │       │       └──► append to TranscriptStore
    │       │               │
    │       │               └──► UI 更新
    │       │
    │       └──► 每 N 分钟（可配置）
    │               │
    │               ▼
    │         Summarizer.trigger()
    │               │
    │               ├──► 收集最近 N 分钟 segments
    │               ├──► 构建 prompt (含上次摘要)
    │               ├──► LLM.generate()
    │               ├──► 创建 SummaryBlock
    │               └──► 通知 UI + 系统通知
    │
    ▼
[用户手动停止 / 定时结束 / 最大时长到达]
    │
    ├──► ASR 最终确认
    ├──► 触发最后一次摘要（如有剩余未总结内容）
    ├──► 生成完整会话摘要 (Final Summary)
    ├──► 保存 RecordingSession
    └──► 清理资源
```

### 6.2 错误恢复

- **ASR 引擎崩溃**：自动重启引擎，从 Ring Buffer 恢复，丢失 < 5s 数据
- **LLM 超时**：重试 3 次，间隔 10s/30s/60s，失败后标记该区间为"待摘要"
- **音频设备断开**：暂停录音，弹出通知，设备恢复后自动继续
- **App 被杀**：音频文件通过 WAV 格式保证可恢复（即使未正常关闭），下次启动时检测未完成的 session

---

## 7. 配置 & 设置

### 7.1 用户可配置项

```swift
struct AppSettings: Codable {
    // — 录音 —
    var audioSource: AudioSource = .microphone
    var audioQuality: AudioQuality = .standard     // standard(16kHz) / high(44.1kHz)
    var maxRecordingDuration: Int? = nil            // 分钟，nil = 无限制
    var silenceTimeout: Int? = 300                  // 静音 N 秒后自动停止
    
    // — ASR —
    var asrEngine: ASREngineType = .whisperLocal
    var whisperModel: WhisperModelSize = .small     // tiny/base/small/medium/large
    var language: String = "auto"                   // auto-detect / zh / en / ja / ...
    var enableSpeakerDiarization: Bool = false
    
    // — 摘要 —
    var summaryInterval: Int = 5                    // 分钟 (1-60)
    var summaryStyle: SummaryStyle = .bullets
    var llmProvider: LLMProvider = .ollama
    var llmModel: String = "llama3.2:3b"
    var llmAPIKey: String? = nil
    var customSystemPrompt: String? = nil
    var enableFinalSummary: Bool = true             // 录音结束时生成完整摘要
    
    // — 通用 —
    var launchAtLogin: Bool = true
    var showInMenuBar: Bool = true
    var showInDock: Bool = false
    var audioStoragePath: String = "~/Documents/LiveScribe/"
    var retentionDays: Int = 30                     // 音频文件保留天数
    var exportFormat: ExportFormat = .markdown       // markdown / txt / json / docx
    
    // — 快捷键 —
    var hotkeyToggleRecording: KeyCombo = .init(key: .r, modifiers: [.command, .shift])
    var hotkeyNewSession: KeyCombo = .init(key: .n, modifiers: [.command, .shift])
}
```

---

## 8. 导出 & 集成

### 8.1 导出格式

| 格式 | 内容 |
|------|------|
| Markdown | 转录 + 摘要 + 时间戳，适合 Obsidian/Notion |
| JSON | 完整结构化数据，含 confidence 等元信息 |
| TXT | 纯文本转录 |
| SRT/VTT | 字幕格式 |
| DOCX | 格式化文档（摘要 + 转录附录） |

### 8.2 集成接口（v2 规划）

- **Webhook**：每次摘要生成后 POST 到自定义 URL
- **Apple Shortcuts**：Shortcuts.app 可触发录音/获取摘要
- **AppleScript / CLI**：`livescribe start --duration 60 --summary-interval 5`
- **Calendar 集成**：读取日历事件，自动在会议开始时录音

---

## 9. 隐私 & 安全

- 所有音频和转录数据默认存储在本地 `~/Documents/LiveScribe/`
- 使用本地 ASR + 本地 LLM 时**零数据外传**
- 使用云端 API 时明确提示用户数据将发送到第三方
- API Key 存储在 macOS Keychain 中
- 录音开始时在菜单栏和通知中心明确提示（macOS 合规要求）
- 支持设置 PIN/Touch ID 解锁应用

---

## 10. 性能指标

| 指标 | 目标值 |
|------|--------|
| 音频到转录文本延迟 | < 3s (本地 whisper.cpp small) |
| 内存占用（录音中） | < 500MB (含 Whisper small 模型) |
| CPU 占用（录音中） | < 30% (Apple Silicon, whisper.cpp) |
| 摘要生成时间 | < 10s (本地 3B 模型) / < 5s (云端) |
| 电池影响 | 录音 1 小时 < 15% 电量 (MacBook Pro M2) |
| 磁盘写入 | ~1MB/min (16kHz WAV) |

---

## 11. 开发里程碑

| 阶段 | 范围 | 预估工期 |
|------|------|---------|
| **M1: MVP** | 手动录音 + whisper.cpp 实时转录 + 文本显示 | 2-3 周 |
| **M2: 摘要** | LLM 集成（Ollama）+ 周期性摘要 + 菜单栏 | 1-2 周 |
| **M3: 定时** | 调度器 + 日程管理 + 系统通知 | 1 周 |
| **M4: 打磨** | 多引擎切换 + 导出 + 设置面板 + 错误恢复 | 2 周 |
| **M5: 增强** | 系统音频采集 + 说话人分离 + Calendar 集成 | 2-3 周 |

---

## 12. 依赖 & 第三方库

| 库 | 用途 | License |
|----|------|---------|
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | 本地 ASR | MIT |
| [llama.cpp](https://github.com/ggerganov/llama.cpp) / Ollama | 本地 LLM | MIT |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 全局快捷键 | MIT |
| [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) | whisper.cpp Swift 封装 | MIT |

---

## 13. 开放问题 & 决策点

1. **系统音频采集方式**：ScreenCaptureKit 需要屏幕录制权限（用户感知较重），是否考虑虚拟音频驱动 (BlackHole) 作为替代？
2. **说话人分离**：是否在 MVP 中支持？本地方案 (pyannote.audio) 性能开销较大。
3. **模型分发**：Whisper 模型文件 (~500MB for small) 是否内置还是首次启动下载？
4. **多语言混合**：用户可能在会议中中英混用，whisper.cpp 的 `language=auto` 在混合语言场景下精度有限，是否需要分段检测？
5. **沙盒 vs 非沙盒**：App Store 分发需要沙盒，但 ScreenCaptureKit 和本地模型路径可能受限。是否 notarized 直接分发？
