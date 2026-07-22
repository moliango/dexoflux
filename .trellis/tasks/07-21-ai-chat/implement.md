# Implementation notes

Phase 2 of the FluxDo AI port: topic AI assistant + AI hub restructure.
New files in `dexo/Features/AIModelService/`:

1. `AIChatModels.swift` — AIChatMessage/AIChatRole, AIContextScope
   (仅主帖/前5/前10/前20/全部, default first5), AIChatSession (Codable, per
   baseURL+topicId), AIPromptPreset with FluxDo's four default prompts
   (文案逐字对齐), AIChatSettings (default scope + custom system prompt in
   UserDefaults).
2. `AIChatStore.swift` — actor; chat-sessions.json (cap 100, sorted by
   updatedAt) + prompt-presets.json (seeded once) under
   ApplicationSupport/DexoFlux/AIModelService.
3. `AIChatService.swift` — system prompt & context builders (formats copied
   verbatim from FluxDo: "#N @user:\n正文", context injected as a fake
   user/assistant pair); streamChat AsyncThrowingStream — openai SSE
   chat/completions, openaiResponse SSE /responses
   (response.output_text.delta), gemini generateContent + anthropic /messages
   single-shot (ponytail ceiling noted); error extraction shared with
   AIProviderAPIError copy.
4. `AIChatSheetViewController.swift` — the sheet: header (AI 助手 + context
   scope menu + more menu 新对话/选择模型), bubble table (user accent right /
   assistant gray left, long-press copy), empty state with FluxDo quick-prompt
   chips + 更多, capsule input bar with send/stop button, streaming updates the
   last cell in-place, sessions restored per topic and persisted after each
   turn; 全部楼层 fetches remaining stream posts capped at 100.
5. `AIChatSupportPages.swift` — AIChatHistoryViewController (list/delete/tap →
   reopen chat sheet directly), AIPromptPresetsViewController (CRUD via
   alert), AIAdvancedSettingsViewController (default context scope + custom
   system prompt).
6. `AIModelServiceViewController.swift` rewritten as the FluxDo-style hub
   (供应商 count / 默认模型 / 聊天记录 / 快捷词管理 / 高级设置); provider
   table moved to new `AIProviderListViewController`; picker + tag formatter
   unchanged. Hub takes `api` (Me passes it; 聊天记录 hidden without it).
7. `TopicDetailViewController` — sparkles nav button between more/search →
   presents the sheet (medium/large detents, undimmed medium).

Deviations (recorded): model switching edits the global default model; preset
sends full prompt but bubbles show the preset title; markdown rendered as
plain text; no attachments/image generation/title auto-gen.

## Verification

- `make generate` + simulator build: BUILD SUCCEEDED, zero errors.
- Device-side: configure a provider → ask 总结这个话题 on a topic (streaming),
  relaunch → 聊天记录 shows the session and reopens it.
