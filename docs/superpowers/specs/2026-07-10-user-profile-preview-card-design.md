# User Profile Preview Card Design

## Goal

Restyle the UIKit user profile preview to use the reference card hierarchy without copying its fixed blue palette. The card must remain compact, theme-aware, and usable on iPhone widths supported by the iOS 15 target.

## Approved Layout

- Present a centered, over-full-screen card with a blurred and dimmed backdrop.
- Keep the avatar suspended over the top-left edge of the card.
- Place the name, username, trust-level pill, and optional title to the right of the avatar without the current oversized fixed spacer.
- Lay out bio, optional location/website, activity facts, social statistics, and actions as full-width rows below the identity block.
- Hide optional title and location/website rows when the API has no value; do not reserve placeholder height.
- Use approximately 22-24 pt horizontal screen margins and a loaded height of at least 330 pt, growing with optional profile content.
- Remove the decorative grabber because this is not an interactive sheet.

## Visual Scale

- Avatar halo: about 64-72 pt overall.
- Display name source size: 18 pt through `AppSettings.appInterfaceFont(...)`.
- Username and trust level: about 11 pt source size.
- Bio: about 12.75 pt source size, up to three lines.
- Metadata and statistics: about 10.25-10.75 pt source size.
- Primary action visual height: 34 pt; secondary action visual height: 32 pt.
- Expand button hit testing to at least 44 pt without enlarging the visible controls.

## Theme Behavior

- Use `ThemeStyle.topicCardBackgroundColor` for the card and avatar surround.
- Use `ThemeStyle.accentColor` for the avatar halo, trust-level pill, watermark, primary button, tinted follow button, and control borders.
- Keep text on semantic UIKit colors so light mode, dark mode, and accessibility contrast continue to work.
- Do not display `cardBackgroundURL` in this compact preview because arbitrary user images can make the text illegible.

## Data And Navigation

- Preserve the existing `UserProfileViewModel` loading flow and all profile formatting helpers.
- Preserve avatar/flair loading, optional field behavior, dismiss interaction, and `onViewProfile` navigation callback.
- Keep unavailable private-message, follow, and more actions unchanged.

## Verification

- Parse the changed Swift file with the Swift frontend.
- Run a full Debug simulator build.
- Check `git diff --check`.
- Inspect the popup in the simulator at a phone width and confirm the compact layout does not clip long names or optional metadata.
