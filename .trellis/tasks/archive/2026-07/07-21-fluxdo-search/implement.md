# Implementation notes

Ported FluxDo's search experience onto the existing native screens
(Features/ForumDetail/Search/).

## Networking

- `DiscourseSearch.swift`: `users` array (`SearchUser`) +
  `more_full_page_results` on grouped result.
- `DiscourseRouter` / `DiscourseAPI`: `semanticSearch(term:)` →
  GET `/discourse-ai/embeddings/semantic-search?q=`; `fetchRecentSearches()` /
  `clearRecentSearches()` → GET/DELETE `/u/recent-searches.json`.

## Filter model & panel

- `SearchFilterPanel.swift` (new): `SearchTopicStatus`
  (open/closed/archived/solved/unsolved), `SearchAdvancedFilter` (multi tags /
  status / after / before → `tags:x status:x after:yyyy-MM-dd before:…` query
  parts, activeCount), `SearchFilterPanelViewController` — sheet with tag
  multi-picker row, status checkmarks, compact date pickers with per-row clear
  buttons, 清除全部; every change fires `onChanged` immediately (FluxDo
  behavior). Deviation: category stays on the existing quick-bar button
  (`category:slug`), not moved into the panel.
- `TagPickerViewController`: multi-select mode added
  (`init(api:categoryId:selectedTags:)` + `onTagsSelected`, Done button,
  toggling checkmarks); single-select API untouched (NewTopicComposer caller).

## ViewModel

- `SearchViewModel`: `advancedFilter` replaces single tag; sort order persisted
  in UserDefaults (`search.sort_order`); server recent searches
  (load/clear); `userResults`; AI semantic search fired in parallel with page-1
  standard search when sort == relevance, results merged via RRF (k=5, same as
  Discourse frontend), `aiTopicIds` = AI-only hits for badging; 403 /
  error_type not_found disables AI for the session, other failures are
  silently ignored per query (FluxDo behavior); generation counter guards
  stale AI responses.

## UI

- `SearchViewController`: quick bar now [分类][排序][筛选·N]; active-filter
  chips bar (horizontal capsules with ×, 清除全部) under the bar; recent
  searches as table backgroundView before first search (tap to run, 清空
  clears server-side); user results as a horizontal chip header above posts
  (pushes UserProfileViewController); result rows reconfigure on AI merge.
- `SearchResultCell`: `isAIResult` renders an "AI" badge after the title
  (indigo, attributed-string chip).

## Verification

- `make generate` (new file) + simulator build: BUILD SUCCEEDED, zero errors.
- Device-side: verify recent searches + AI merge on linux.do (discourse-ai
  enabled) and graceful degradation on a forum without the plugin.
