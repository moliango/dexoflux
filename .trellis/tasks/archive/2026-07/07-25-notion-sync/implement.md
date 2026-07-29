# Implement — Notion Sync

1. [x] Config store + client + converter + sync service
2. [x] Settings page + Me entry
3. [x] Topic detail sync action + duplicate dialog
4. [x] Unit tests converter
5. [x] build + tests

## Validation
- build-for-testing OK
- NotionMarkdownConverterTests 2/2

## Residual
- Bookmark auto-sync setting is stored but not yet hooked into bookmark action
- Markdown conversion is line-based (not full GFM AST)
