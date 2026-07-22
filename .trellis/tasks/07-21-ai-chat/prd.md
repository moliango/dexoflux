# Port FluxDo AI chat (topic assistant + AI hub)

## Scope

Phase 2 of the FluxDo AI port (phase 1 = provider/model management, task
07-21-ai-model-service).

1. AI 模型服务 hub page restructured to FluxDo AiProvidersPage layout:
   供应商 (count subtitle) / 默认模型 / 聊天记录 / 快捷词管理 / 高级设置;
   provider list moves to its own page.
2. Topic detail AI assistant sheet (FluxDo ai_chat_page):
   - Nav sparkles button on TopicDetailViewController → sheet (medium/large).
   - Header: AI 助手 title + context scope menu (仅主帖/前5/前10/前20/全部楼层,
     default 前 5 楼) + more menu (新对话 / 选择模型).
   - Empty state: 向 AI 助手提问 + quick prompt chips (FluxDo default four:
     总结这个话题/翻译主帖/列出主要观点/有什么值得关注的 + 更多).
   - Context injection identical to FluxDo: system prompt (助手介绍 + 话题标题 +
     上下文提示 + Markdown 要求) and a fake user/assistant pair
     ("以下是话题内容：\n#N @user:\n正文…" → "好的，我已经阅读了话题内容…").
   - Streaming responses for OpenAI-compatible providers (SSE
     chat/completions), OpenAI-Response via /responses SSE; Gemini/Anthropic
     single-shot (ponytail ceiling).
   - Sessions persisted locally per topic; reopening the sheet restores the
     latest session; 新对话 starts fresh.
3. 聊天记录 page: local session list (delete swipe); tap reopens the chat
   sheet directly.
4. 快捷词管理: preset CRUD (seeded with FluxDo defaults), used by the chips.
5. 高级设置: default context scope + custom system prompt.

## Non-goals

- Image generation/attachments, thinking budget, AI post review, title
  auto-generation, app-network routing switches, per-chat model override
  (model switching edits the global default).

## Acceptance

- [ ] With a configured default model, asking 总结这个话题 streams an answer
      grounded in the topic content.
- [ ] Sessions survive app relaunch and appear in 聊天记录.
- [ ] No default model → sheet shows guidance to configure one.
- [ ] make generate + simulator build succeed.
