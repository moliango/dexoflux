# Design — share image polish

## Approach
- Replace direct `UIActivityViewController` with `ShareImagePreviewViewController` sheet.
- Card built by `ShareImageCardView` (logo/brand, title emoji, author, cooked HTML body, link).
- Themes mirror FluxDO colors; index persisted in UserDefaults.
- Capture via `UIGraphicsImageRenderer` / layer render of card host view.
- Entry: topic menu default main post; optional `postId` for specific floor.

## Tradeoffs
- Body uses HTML→NSAttributedString, not full native block renderers (acceptable MVP parity for share cards).
