# Changelog

## [2026-03-24]

- Security review and fixes: resolved VAD data race (CRITICAL), multi-clip audio deletion, prompt injection mitigation, resultTask timeout cancellation, NoopASREngine thread safety, Keychain empty-key guard, migration failure cleanup, URL scheme validation, HTTP error truncation, smart retry logic, API key leak warning, and sensitive data logging cleanup
  Files: AudioCaptureService.swift, SessionListView.swift, PromptBuilder.swift, SpeechAnalyzerEngine.swift, NoopASREngine.swift, LLMConfig.swift, LLMModelProfile.swift, KeychainMigration.swift, LLMEngine.swift, OpenAIEngine.swift, OllamaEngine.swift, AnthropicEngine.swift, SummarizerService.swift, BackgroundSummaryService.swift, SettingsView.swift, CrashLogService.swift, PromptBuilderTests.swift
