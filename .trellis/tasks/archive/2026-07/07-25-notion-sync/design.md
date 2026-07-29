# Design — Notion Sync

## Components
- `NotionConfigStore`：Keychain token + UserDefaults meta
- `NotionClient`：api.notion.com v1 GET/POST/PATCH
- `NotionMarkdownConverter`：line-based md → blocks
- `NotionSyncService`：export posts → blocks → create/append
- `NotionSettingsViewController`
- TopicDetail menu entry

## Schema (database properties)
Name(title), URL(url), Topic ID(number), Post ID(number), Author(rich_text), Created(date), Synced(date)

## Security
Token: Keychain service `com.naine.dexoflux.notion` account = scopeKey
