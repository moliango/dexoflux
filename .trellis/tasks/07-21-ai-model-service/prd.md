# Port FluxDo AI model service (provider management core)

## Background

FluxDo's "AI 模型服务" is backed by its local `ai_model_manager` Flutter package
(~12k lines: provider management, topic AI chat, prompt presets, chat history,
advanced settings). Dexo has none of it. A full port is multi-phase; this task
ports the **model service management core** — the part the profile entry opens.

Reference files (repo /Users/naine/Documents/AndroidWorkspace/fluxdo):
- packages/ai_model_manager/lib/models/ai_provider.dart (types/models JSON shape)
- packages/ai_model_manager/lib/services/ai_provider_service.dart (fetch/test)
- packages/ai_model_manager/lib/utils/api_host_formatter.dart (base-URL rules)
- packages/ai_model_manager/lib/utils/model_capabilities.dart (capability regex)
- pages: ai_providers_page / ai_provider_list_page / ai_provider_edit_page

## Scope

1. Models: AIProviderType (openai / openaiResponse / gemini / anthropic with
   default base URLs), AIModel (id, name, enabled, input/output modalities,
   abilities, capabilitiesUserEdited — FluxDo JSON-compatible), AIProvider
   (id, name, type, base_url, models, pinned).
2. Capability inference ported from model_capabilities.dart (vision / reasoning
   / tool / imageOutput / embedding regexes) for tag display after fetch.
3. Store (actor): providers JSON under ApplicationSupport/DexoFlux/AIModelService,
   API keys in Keychain; default model ref (provider|model) in UserDefaults.
4. AIProviderAPIService: formatAPIHost (`#` strict / existing /vN respected /
   else append /v1 or /v1beta), fetchModels per type (anthropic = static list),
   testModel minimal 1-token request per protocol, friendly error mapping.
5. UI (native, app card style): main page (默认模型 picker row + 供应商 list +
   add via type sheet), provider edit page (name / base URL / API key fields,
   拉取模型 with enabled-state-preserving merge, per-model enable switches with
   capability tags, 测试连接, delete), Me tab entry "AI 模型服务".

## Non-goals (follow-up phases)

- Topic AI chat, chat history, prompt presets, advanced settings, thinking
  config, streaming client, AI post review.
- Manual capability editing (inference only for now).

## Acceptance

- [ ] Add an OpenAI-compatible provider (e.g. NewAPI gateway), fetch models,
      enable some, pick a default model, test connectivity.
- [ ] Keys never land in the JSON file (Keychain only).
- [ ] Simulator build succeeds after `make generate` (new files).
