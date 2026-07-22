# Port FluxDo search experience

## Background

Dexo's search (Features/ForumDetail/Search/) supports term + single category +
single tag + sort. FluxDo's search (lib/pages/search_page.dart +
models/search_filter.dart + services/discourse/_search.dart) adds server-side
recent searches, an advanced filter model, active-filter chips, user results,
and Discourse-AI semantic search merged via RRF. Port those onto the existing
native screens.

## Scope (FluxDo parity)

1. SearchFilter: multiple tags (`tags:x`), topic status
   (open/closed/archived/solved/unsolved → `status:x`), date range
   (`after:`/`before:` YYYY-MM-DD), category `#slug` / `#parent:child` syntax;
   activeFilterCount for the badge.
2. Advanced filter panel (sheet): status single-select, after/before date rows
   with compact date pickers, multi-tag selection (TagPicker gains multi mode),
   clear-all; changes re-run the search immediately (FluxDo behavior).
3. Active filters chip bar under the quick-filter bar: one capsule per active
   condition with ×, plus 清除全部.
4. Recent searches: GET/DELETE `/u/recent-searches.json`; shown when no search
   has run (tap to search, 清空 to clear server-side).
5. AI semantic search: GET `/discourse-ai/embeddings/semantic-search?q=` fired
   in parallel with page-1 standard search when sort is relevance; results
   merged with Reciprocal Rank Fusion (k=5, same as Discourse frontend);
   AI-sourced rows get an AI badge; 403/404/errors silently disable for the
   session.
6. User results: `users` parsed from search.json, shown as a horizontal chip
   row above post results, tapping opens the user profile.
7. Sort order persisted across sessions (FluxDo persists in settings).

## Non-goals

- Search preview dialog (post peek), in-topic search view changes, user-content
  search page (bookmarks/created/seen scopes), AI search user toggle.

## Acceptance

- [ ] Filters compose into the correct Discourse query string.
- [ ] Recent searches load/clear against the live forum.
- [ ] AI merge path works on linux.do (site has discourse-ai) and silently
      degrades elsewhere.
- [ ] make generate + simulator build succeed.
