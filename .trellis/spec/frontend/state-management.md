# State Management

> How state is managed in this project.

---

## Overview

<!--
Document your project's state management conventions here.

Questions to answer:
- What state management solution do you use?
- How is local vs global state decided?
- How do you handle server state?
- What are the patterns for derived state?
-->

(To be filled by the team)

---

## State Categories

<!-- Local state, global state, server state, URL state -->

(To be filled by the team)

---

## When to Use Global State

<!-- Criteria for promoting state to global -->

(To be filled by the team)

---

## Server State

<!-- How server data is cached and synchronized -->

### Discourse Web Auth State

- Treat the `_t` cookie as the only proof of a logged-in Discourse web session.
- Do not use `_forum_session` or other `*_session` cookies as login proof; those can exist for anonymous browser sessions.
- When an authenticated API response fails with `401`, `403`, or an empty serialized body, try one forced WebView cookie refresh before clearing local auth state.
- Merge response `Set-Cookie` headers only after Cloudflare and auth-recovery checks, so a transient auth failure cannot delete the recoverable `_t` cookie before recovery runs.
- Cloudflare verification UI must sync only `cf_clearance` from its WebView; never bulk-sync `_t` or `_forum_session` from the challenge page.
- Update the stored WebView `User-Agent` only after Cloudflare verification succeeds, because `cf_clearance` is User-Agent sensitive.
- Treat `WKHTTPCookieStoreObserver` callbacks as high-frequency and potentially overlapping; completion handlers must be serialized and idempotent before posting notifications or dismissing UI.

---

## Common Mistakes

<!-- State management mistakes your team has made -->

(To be filled by the team)
