# Implement — topic title emoji fix

1. [x] Add unit tests for `EmojiStore.resolvedURL` and shortcode attributed rendering.
2. [x] Implement store resolution + didUpdate notification.
3. [x] Add `TitleEmojiRenderer` shared helper.
4. [x] Wire `TopicCell` + `TopicDetailViewController` to renderer and refresh.
5. [x] Pass forum baseURL into title configure paths where missing.
6. [x] Run tests / build.

## Validation

- `mise exec -- tuist generate` OK
- `xcodebuild build-for-testing` (`dexofluxTests`) OK
- `TitleEmojiRendererTests` 6/6 passed

## Notes

- Xiaohongshu card titles also use `TitleEmojiRenderer`.
- Share-image child should reuse `TitleEmojiRenderer` for card titles.
