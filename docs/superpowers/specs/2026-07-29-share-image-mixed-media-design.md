# Share Image Mixed Media (Approach B)

## Goal
Share cards render post body as ordered text + real images, not image URLs.

## Design
- Parse cooked HTML with `PostImageLinkPreprocessor` + `CookedHTMLParser`.
- Flatten to segments: text / image URL / more-images footnote.
- Cap content images at 6; max image height ~240pt.
- `ShareImageCardView` lays out body as vertical stack (labels + image views).
- Load images via `ExternalImageFetcher` / cache; gate save/share until ready or 2.5s timeout.
- Failures show placeholder; never block forever.

## Out of scope
Video/GIF animation, full quote/table fidelity, AI share cards.
