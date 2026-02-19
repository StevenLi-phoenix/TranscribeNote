# App Store Privacy & Submission Checklist

Developer guide for preparing the Notetaker app for App Store Connect submission.

---

## 1. Privacy Nutrition Labels

In **App Store Connect > App Privacy**:

### Data Types

Select **"No, we do not collect data from this app"**.

**Rationale:** Notetaker itself does not collect any data. The user may optionally configure a third-party LLM API, but the app acts as a conduit — similar to a web browser making requests to user-specified URLs. The data is sent directly from the user's device to their chosen API endpoint.

If Apple's review team asks about network requests, explain:

> "Network requests are made only when the user explicitly configures a third-party LLM provider in Settings. The user provides their own API key and chooses the endpoint. No data is sent to the developer or any developer-controlled server. The app includes a just-in-time privacy disclosure before LLM configuration."

---

## 2. Privacy Policy URL

### Hosting

Host `PRIVACY_POLICY.md` at a public URL. Options:

1. **GitHub Pages** (recommended): `https://<username>.github.io/notetaker/privacy`
2. **GitHub raw**: `https://github.com/<username>/notetaker/blob/main/docs/PRIVACY_POLICY.md`
3. **Custom domain**: Your own website

### App Store Connect Configuration

In **App Store Connect > App Information > Privacy Policy URL**: Enter the hosted URL.

---

## 3. App Review Notes

Copy and customize this template for **App Store Connect > App Review Information > Notes**:

```
NETWORK USAGE:

Notetaker makes network requests ONLY when the user explicitly configures
an LLM provider in Settings > Live LLM or Settings > Overall LLM. These
requests send transcript text to the user's chosen API endpoint (OpenAI,
Anthropic, or a custom OpenAI-compatible server) for AI-powered
summarization.

No data is sent to the developer. No analytics, telemetry, or tracking
of any kind is included.

A privacy disclosure modal is shown the first time the user opens the
LLM Settings tab, before any configuration is possible.

ENTITLEMENTS:

- com.apple.security.app-sandbox: Required for App Store distribution
- com.apple.security.device.audio-input: Records audio for transcription
  via Apple's on-device Speech framework
- com.apple.security.files.user-selected.read-write: Saves audio
  recordings to user-selected locations
- com.apple.security.network.client: Sends transcript text to
  user-configured LLM API endpoints for summarization

TESTING:

To test summarization, configure a local LM Studio instance at
http://localhost:1234/v1 (default settings) or provide an OpenAI/
Anthropic API key in Settings.

Audio recording requires microphone access — grant permission when
prompted.
```

---

## 4. Entitlements Justification

| Entitlement | Purpose |
|---|---|
| `com.apple.security.app-sandbox` | Required for App Store distribution |
| `com.apple.security.device.audio-input` | Records audio for transcription via Apple's on-device Speech framework |
| `com.apple.security.files.user-selected.read-write` | Saves audio recordings to user-accessible locations |
| `com.apple.security.network.client` | Sends transcript text to user-configured LLM API endpoints |

---

## 5. Third-Party Code Disclosure

Currently, Notetaker uses **no third-party SDKs or frameworks**. All functionality is built on Apple frameworks:

- SwiftUI (UI)
- SwiftData (persistence)
- Speech / SpeechAnalyzer (ASR)
- AVFoundation (audio)
- MetricKit (crash diagnostics)
- Security (Keychain)

If third-party dependencies are added in the future, disclose them in App Store Connect.

---

## 6. In-App Privacy Disclosure

The app includes a just-in-time privacy disclosure:

1. **First access**: A modal sheet appears the first time the user opens any LLM Settings tab
2. **Content**: Explains what data is sent, where, and that the user controls everything
3. **Acknowledgment**: User must tap "I Understand" to dismiss
4. **Re-access**: Available via Help > Data Usage Information menu

This meets Apple's requirement for "just-in-time" disclosure before data collection.

---

## 7. Pre-Submission Checklist

- [ ] Privacy policy hosted at public URL
- [ ] Privacy policy URL entered in App Store Connect > App Information
- [ ] Privacy Nutrition Labels configured ("No data collected")
- [ ] App Review notes include network request explanation
- [ ] App Review notes include entitlements justification
- [ ] In-app privacy disclosure modal works (reset with: `defaults delete <bundle-id> hasShownPrivacyDisclosure`)
- [ ] Help menu includes "Privacy Policy" and "Data Usage Information" items
- [ ] All screenshots updated for App Store listing
- [ ] App builds and runs on macOS 26.2+
- [ ] All tests pass: `xcodebuild -scheme notetaker -configuration Debug test`
