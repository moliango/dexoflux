# Design — topic title emoji fix

## Root cause

1. Early return when `EmojiStore.lookupMap.isEmpty` leaves raw shortcodes.
2. No refresh when `loadOrFetchEmojiMap()` later succeeds.
3. Standard emoji resolution is map-only; FluxDO also has deterministic path fallback.

## Approach

1. Extend `EmojiStore` with `resolvedURL(for:baseURL:)`:
   - normalize code / alias
   - prefer cached lookup map URL
   - else if baseURL present, build `/images/emoji/twitter/{name}.png?v=12` (and tone variants if needed)
2. Add `TitleEmojiRenderer` producing `NSAttributedString` + attachment load callback.
3. Replace duplicated logic in `TopicCell` and `TopicDetailViewController`.
4. Post `EmojiStore.didUpdateNotification` after load/save; list/detail re-apply titles.
5. TopicCell keeps last title + baseURL for refresh; configure passes categoryBaseURL/forum baseURL.

## Tradeoffs

- Deterministic standard URL may 404 for invalid names; keep shortcode text as image load failure fallback or only replace when map hit / known alias.
- Prefer: if map hit use map; if map empty or miss, still attempt deterministic URL for shortcode-shaped names (FluxDO behavior). Image load failure leaves empty attachment risk — reassign attributed string after load, or keep shortcode until image arrives.

Safer UX: create attachment only when URL resolved; on image load failure optionally restore shortcode text. First pass: attachment + load; if load fails, leave blank or shortcode — match current list behavior (attachment with image set async).
