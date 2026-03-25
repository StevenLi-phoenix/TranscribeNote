# SPEC-003: 多格式导出 (Rich Export Formats)

## 状态: 待实现 | 优先级: 低 | 里程碑: M4

---

## 1. 概述

扩展现有导出能力，支持 Markdown、JSON、SRT/VTT 字幕格式导出。当前仅有纯文本复制到剪贴板和音频 M4A 导出。

## 2. 目标

- 支持 5 种导出格式：Markdown / JSON / TXT / SRT / VTT
- 导出内容包含：转录文本 + 摘要 + 时间戳 + 元信息
- 通过 NSSavePanel 选择保存路径
- DOCX 列为 v2 考虑（依赖重，优先级低）

## 3. 格式定义

### 3.1 Markdown (.md)

适合 Obsidian / Notion 等知识管理工具。

```markdown
# 会议标题
**日期:** 2026-03-13 14:00 - 15:30
**时长:** 1小时30分钟
**标签:** #会议 #项目

---

## 摘要

### 14:00 - 14:05
- 讨论了 Q2 预算分配方案
- 决定增加研发投入 20%

### 14:05 - 14:10
- 产品路线图 review
- [用户编辑] 确认 v2.0 发布日期为 4 月 15 日

---

## 完整转录

[00:00:12] 大家好，今天我们讨论一下 Q2 的预算。
[00:00:25] 我觉得研发这块需要加大投入。
...
```

### 3.2 JSON (.json)

完整结构化数据，可供程序消费。

```json
{
  "session": {
    "id": "uuid",
    "title": "会议标题",
    "startedAt": "2026-03-13T14:00:00Z",
    "endedAt": "2026-03-13T15:30:00Z",
    "totalDuration": 5400,
    "tags": ["会议", "项目"]
  },
  "transcriptSegments": [
    {
      "id": "uuid",
      "startTime": 12.0,
      "endTime": 18.5,
      "text": "大家好，今天我们讨论一下 Q2 的预算。",
      "confidence": 0.95,
      "language": "zh",
      "speakerLabel": null
    }
  ],
  "summaries": [
    {
      "id": "uuid",
      "generatedAt": "2026-03-13T14:05:00Z",
      "coveringFrom": 0,
      "coveringTo": 300,
      "content": "讨论了 Q2 预算分配方案...",
      "editedContent": null,
      "style": "bullets",
      "model": "qwen3-14b-mlx",
      "isPinned": false,
      "isOverall": false
    }
  ]
}
```

### 3.3 SRT (.srt)

```
1
00:00:12,000 --> 00:00:18,500
大家好，今天我们讨论一下 Q2 的预算。

2
00:00:25,000 --> 00:00:32,100
我觉得研发这块需要加大投入。
```

### 3.4 VTT (.vtt)

```
WEBVTT

00:00:12.000 --> 00:00:18.500
大家好，今天我们讨论一下 Q2 的预算。

00:00:25.000 --> 00:00:32.100
我觉得研发这块需要加大投入。
```

### 3.5 TXT (.txt)

现有 `TranscriptExporter.formatAsText()` 已实现，保持不变。

## 4. 技术方案

### 4.1 ExportService

```swift
enum ExportFormat: String, CaseIterable {
    case markdown = "md"
    case json = "json"
    case txt = "txt"
    case srt = "srt"
    case vtt = "vtt"
}

struct ExportService {
    static func export(
        session: RecordingSession,
        format: ExportFormat
    ) -> String {
        switch format {
        case .markdown: return exportMarkdown(session)
        case .json:     return exportJSON(session)
        case .txt:      return exportTXT(session)
        case .srt:      return exportSRT(session)
        case .vtt:      return exportVTT(session)
        }
    }

    static func saveToFile(
        content: String,
        filename: String,
        format: ExportFormat
    ) async -> URL? {
        // NSSavePanel with suggested filename
    }
}
```

### 4.2 UI 集成

`SessionDetailView` toolbar 添加导出菜单：

```swift
Menu {
    ForEach(ExportFormat.allCases, id: \.self) { format in
        Button("导出为 .\(format.rawValue)") {
            exportSession(format: format)
        }
    }
} label: {
    Label("导出", systemImage: "square.and.arrow.up")
}
```

## 5. 影响范围

| 文件 | 变更 |
|------|------|
| 新增 `Services/ExportService.swift` | 导出格式化逻辑 |
| `SessionDetailView.swift` | 导出菜单按钮 |
| `TranscriptExporter.swift` | 可复用现有 TXT 格式化，或合并到 ExportService |

## 6. 测试计划

- [ ] 单元测试：每种格式的输出格式验证
- [ ] 边界：空 session（无转录/无摘要）不崩溃
- [ ] 编码：中文字符正确输出（UTF-8）
- [ ] SRT/VTT 时间戳格式符合标准

## 7. 不做

- DOCX 导出：需引入第三方库（如 DocX），推迟到 v2
- Webhook 推送：推迟到 v2
