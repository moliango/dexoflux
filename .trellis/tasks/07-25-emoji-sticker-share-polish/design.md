# Design — 表情包、分享图美化与标题 Emoji

## Architecture

Parent 只做边界与集成约束；实现落在 3 个 child。

```
Topic Title Emoji Fix
  └─ shared TitleEmojiRenderer + EmojiStore resolution
       ↑ reused by Share Image title rendering

Share Image Polish
  └─ ShareImagePreviewController + ShareImageRenderer + themes

Sticker Pack
  └─ StickerMarketService + StickerStore + EmojiStickerPanel
       └─ Reply/NewTopic composers
```

## Cross-child contracts

1. **Title emoji rendering** must be a shared utility, not copy-pasted UILabel logic.
2. **Share image** consumes the same shortcode→image resolution for titles.
3. **Stickers** insert Markdown images; post rendering already handles images and must keep working.
4. Sticker market is external HTTP (not Discourse auth). Default base `https://s.pwsh.us.kg`, configurable, cache-isolated from Discourse emoji cache.

## Compatibility

- UIKit only, iOS 15+
- Do not break existing Discourse emoji picker/reactions
- Prefer editing existing composer/detail files over inventing parallel surfaces

## Delivery order

1. `topic-title-emoji-fix`
2. `share-image-polish` (benefits from title renderer)
3. `sticker-pack`
