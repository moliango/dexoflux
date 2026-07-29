# Implementation notes

New feature dir `dexo/Features/AIModelService/` (4 files), ported from FluxDo's
`packages/ai_model_manager` management core:

1. `AIModelServiceModels.swift` — `AIProviderType`
   (openai/openaiResponse/gemini/anthropic + default base URLs), `AIModel` /
   `AIProvider` with FluxDo-compatible JSON keys (base_url, models[], input/
   output/abilities/capabilitiesUserEdited), `AIDefaultModelRef`
   ("providerID|modelID"), `AIModelCapabilities` — the five inference regexes
   (vision/reasoning/tool/imageOutput/embedding) ported verbatim to ICU syntax.
2. `AIModelServiceStore.swift` — actor; providers.json under
   ApplicationSupport/DexoFlux/AIModelService; API keys in Keychain (service
   com.naine.dexoflux.ai-model-service, account = provider id); default model
   ref in UserDefaults; deleting a provider clears its key + default ref.
3. `AIProviderAPIService.swift` — `formatAPIHost` (# strict / existing /vN kept
   / auto-append v1 or v1beta), fetchModels (openai GET /models Bearer; gemini
   GET v1beta/models?key= with models/ prefix strip; anthropic preset list),
   `testModel` minimal 1-token request per protocol, friendly HTTP error
   mapping (401/403/404/429/5xx + error.message extraction).
4. `AIModelServiceViewController.swift` — main page: 默认模型 row (opens
   grouped picker with capability tags + checkmark) + 供应商 list (type icon,
   host, enabled count; swipe delete; add via type action sheet) + empty row.
   `AIDefaultModelPickerViewController` + `AIModelTagFormatter` included.
5. `AIProviderEditViewController.swift` — name/baseURL/apiKey fields (edit mode
   keeps stored key when field left empty), 拉取模型 (merge preserves enabled +
   user-edited capabilities), per-model enable switches with tag subtitles,
   测试连接 (first enabled model), 删除供应商.
6. `MeViewController` — "AI 模型服务" entry (cpu.fill, teal) after 内置浏览器,
   pushing `AIModelServiceViewController` (mirrors FluxDo profile placement).

Deferred (per PRD non-goals): topic AI chat, chat history, prompt presets,
advanced settings, streaming client, manual capability editing.

## Verification

- `make generate` (new files) + simulator build: BUILD SUCCEEDED, zero errors.
- Device-side: add a real NewAPI gateway provider, fetch models, enable, set
  default, run 测试连接.
