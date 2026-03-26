# SPEC-006: LLM Structured Output Support (JSON Schema)

**Issue:** #55
**Date:** 2026-03-26
**Status:** Draft

## Overview

Add structured output (JSON schema-constrained generation) to the `LLMEngine` protocol, enabling engines to return validated JSON conforming to a caller-defined schema. This is the prerequisite for #44 (structured summaries).

## Motivation

`LLMEngine.generate()` returns free-form text via `LLMMessage`. Features like action item extraction (#44) need structured data. Each LLM provider supports schema-constrained output through different mechanisms — this spec unifies them behind a single protocol method.

## Design

### New Types

#### `JSONSchema`

Represents a JSON Schema definition for structured output. Uses raw `Data` for maximum flexibility — no custom DSL to maintain.

```swift
nonisolated struct JSONSchema: Sendable {
    let name: String
    let description: String
    let schemaData: Data   // Raw JSON Schema bytes
    let strict: Bool       // Enforce strict schema adherence

    init(name: String, description: String, schemaData: Data, strict: Bool = true)
}
```

`schemaData` contains a standard JSON Schema object (e.g., `{"type": "object", "properties": {...}, "required": [...]}`). Engines embed it directly into their provider-specific request format.

#### `StructuredOutput`

```swift
nonisolated struct StructuredOutput: Sendable {
    let data: Data           // Raw JSON bytes from LLM
    let usage: TokenUsage?

    func decode<T: Decodable>(_ type: T.Type) throws -> T
}
```

### Protocol Extension

```swift
protocol LLMEngine: AnyObject, Sendable {
    // Existing
    func generate(messages: [LLMMessage], config: LLMConfig) async throws -> LLMMessage
    func isAvailable(config: LLMConfig) async -> Bool

    // New — structured output
    var supportsStructuredOutput: Bool { get }
    func generateStructured(
        messages: [LLMMessage],
        schema: JSONSchema,
        config: LLMConfig
    ) async throws -> StructuredOutput
}
```

Default implementation (protocol extension):

```swift
extension LLMEngine {
    var supportsStructuredOutput: Bool { false }
    func generateStructured(
        messages: [LLMMessage],
        schema: JSONSchema,
        config: LLMConfig
    ) async throws -> StructuredOutput {
        throw LLMEngineError.notSupported
    }
}
```

### Error Handling

Add to `LLMEngineError`:

```swift
case notSupported       // Engine does not support this operation
case schemaError(String) // Invalid schema or schema validation failure
```

`SummarizerService.isRetryable()` treats both as **non-retryable**.

### Per-Engine Implementation

#### OpenAI Engine

**Mechanism:** `response_format` with `json_schema` type.

Request body additions:
```json
{
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "<schema.name>",
      "strict": true,
      "schema": <schema.schemaData as JSON object>
    }
  }
}
```

Response: JSON string in `choices[0].message.content` — parse to `Data`.

#### Anthropic Engine

**Mechanism:** `output_config.format` (GA for Claude 4.5+ models, no beta header needed).

Request body additions:
```json
{
  "output_config": {
    "format": {
      "type": "json_schema",
      "schema": <schema.schemaData as JSON object>
    }
  }
}
```

Response: JSON in `content[0]` text block — parse to `Data`.

#### Ollama Engine

**Mechanism:** `format` parameter on `/api/generate`.

Request body additions:
```json
{
  "format": <schema.schemaData as JSON object>
}
```

Response: JSON string in `response` field — parse to `Data`.

#### FoundationModels Engine

**`supportsStructuredOutput = false`.**

Apple's `@Generable` macro requires compile-time Swift types — no runtime JSON schema API. Future: define `@Generable` structs for known use cases.

#### Noop Engine

**`supportsStructuredOutput = false`.** Uses default implementation.

### Testing Strategy

Each engine gets structured output tests in their existing test files:
- Reuse per-suite `MockURLProtocol` subclasses
- `.serialized` trait (matching existing engine test suites)
- Test cases: happy path, schema embedding in request, token usage, error paths, default `notSupported`

### File Changes

| File | Change |
|------|--------|
| `Services/LLMEngine.swift` | Add `JSONSchema`, `StructuredOutput`, error cases, protocol extension |
| `Services/OpenAIEngine.swift` | Implement `generateStructured()` with `response_format` |
| `Services/AnthropicEngine.swift` | Implement `generateStructured()` with `output_config.format` |
| `Services/OllamaEngine.swift` | Implement `generateStructured()` with `format` param |
| `Services/SummarizerService.swift` | Add `.notSupported`/`.schemaError` to non-retryable errors |
| `notetakerTests/` | Add structured output tests to existing engine test files |

### Scope Boundaries

**In scope:** Protocol extension, types, OpenAI/Anthropic/Ollama implementations, error handling, tests.

**Out of scope:** FoundationModels `@Generable`, callers (#44), full tool calling, streaming.
