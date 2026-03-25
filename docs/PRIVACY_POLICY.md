# Notetaker Privacy Policy

**Last Updated:** February 2026

Notetaker is a macOS note-taking and transcription application. This policy explains how your data is handled.

---

## What Data Stays on Your Device

All core functionality runs locally on your Mac:

- **Audio recordings** are saved to your local disk only.
- **Transcripts** are generated on-device using Apple's Speech framework.
- **Session history** is stored in a local SwiftData database.
- **API keys** are stored in the macOS Keychain, never transmitted to us.
- **App settings** are stored in local UserDefaults.

Notetaker does **not** operate any cloud servers. We do not collect, store, or have access to any of your data.

---

## When Data Leaves Your Device

If you enable the **LLM summarization** feature, Notetaker sends data to a third-party API endpoint that **you** configure:

### What is sent

- Transcript text from your recordings (the text content, not audio).
- Optional context from previous summaries (if "Include Previous Context" is enabled in settings).

### Where it is sent

- The API endpoint you specify in Settings (e.g., OpenAI, Anthropic, a local Ollama instance, or any OpenAI-compatible server).
- The request includes your API key (provided by you) for authentication with the third-party service.

### When it is sent

- During a recording session, at the interval you configure (default: every 5 minutes).
- When you manually trigger summary generation from the session detail view.
- During the overall summary generation after a recording ends.

### What is NOT sent

- Audio files are never transmitted.
- Your API keys are never sent to us (only to the provider you configure).
- Session metadata (timestamps, filenames) is not included in LLM requests.

---

## Third-Party Services

When you configure an external LLM provider, that provider's privacy policy governs how they handle the transcript data you send:

- **OpenAI**: [Privacy Policy](https://openai.com/policies/privacy-policy)
- **Anthropic**: [Privacy Policy](https://www.anthropic.com/privacy)
- **Local providers** (Ollama, LM Studio): Data stays on your local network.
- **Custom endpoints**: Refer to the provider's privacy policy.

We encourage you to review the privacy policy of whichever provider you choose.

---

## Your Control

You have full control over data transmission:

- **Opt-in only**: No data is sent unless you configure an LLM provider and API key.
- **Choose your provider**: Use a local provider (Ollama, LM Studio) to keep everything on your machine.
- **Choose when**: You control the summarization interval and can trigger summaries manually.
- **Revoke access**: Remove your API key from Settings at any time to stop all external requests.

---

## Data We Collect

**None.** Notetaker does not collect analytics, telemetry, crash reports, or any usage data. We have no servers and no way to receive your data.

The only network requests Notetaker makes are to the LLM API endpoint you configure, and only when summarization is actively triggered.

---

## Crash Diagnostics

Notetaker uses Apple's MetricKit framework to receive crash diagnostic information from the operating system. This data is processed locally on your device to display crash information in the app's logs. It is never transmitted externally.

---

## Children's Privacy

Notetaker does not knowingly collect data from children under 13. Since we collect no data at all, this concern does not apply.

---

## Changes to This Policy

We may update this policy when new features are added. Significant changes will be communicated through the app's release notes.

---

## Contact

For questions about this privacy policy:

- GitHub Issues: [github.com/StevenLi-phoenix/notetaker/issues](https://github.com/StevenLi-phoenix/notetaker/issues)
