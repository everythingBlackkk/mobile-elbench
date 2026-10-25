# Changelog

The ElBench app for Android and iOS. Server changes are listed in the backend's changelog
([everythingBlackkk/myFamily](https://github.com/everythingBlackkk/myFamily/blob/main/CHANGELOG.md)).

## 3.0.0 (16) — 2026-10-25

- **Pull to refresh:** a subtle haptic confirms when a refresh starts; scrolling, canceled pulls and automatic reloads stay silent.
- **Schedule:** uses the same platform-adaptive refresh spinner as other pages, keeps the selected day and filters, and refreshes cached content and badges.
- **Releases:** Android uses Shorebird for signed over-the-air updates. iOS uses standard Flutter builds without the Shorebird updater.

## 2.5.2 (14) — 2026-10-25

- **Edit subjects:** Cancel (black) and Save (green) sit side by side across the full width, directly above the active-subjects summary. Save stays faded until you change something; saving takes you back to Home, and Cancel returns Home without saving.

## 2.5.1 (13) — 2026-10-25

Needs backend v8.11.2 or later. Replaces 2.5.0, which was tagged but never shipped.

- **Subject page:** "Ask question" and "My questions" share the row equally (admins also get "Manage" as a third equal button); the bell sits on the same line as the subject's name and opens the full notifications page.
- **Edit subjects:** a plain "Save changes" button at the end of the page appears once you change something; the floating bar is gone.
- **Schedule:** in dark mode the page is the same plain black as the rest of the app.
- **Pull to refresh (Android):** a cleaner spinner in the brand green with rounded ends on a chip that matches the page.
- **Loading:** subject notifications, materials and feed moderation show a list skeleton, Edit subjects shows tiles and the campus map a placeholder block; the parsed campus map is kept in memory, so reopening it is instant. A subject's notifications always refresh when opened.

## 2.5.0 (12) — 2026-10-25

Needs backend v8.11 or later.

- **Subject notifications:** a bell next to each subject's name shows how many notifications you haven't seen. The subject page shows only the latest one; the bell or "See all" opens a full page of the subject's notifications, one after another with their time, loading 10 at a time as you scroll. Opening it marks them as seen.
- **Notify followers:** admins write the notification on a full-screen page like Create post; it reaches followers as a real push notification with the subject as its title.
- **Feed moderation:** admins with the new permission get Admin › Feed moderation (find a student by ID, their latest posts and comments, delete with confirmation) and Delete in the ⋮ menu of any public post or comment.
- **Campus map:** buildings are buttons with their Arabic names; tapping one shows the rooms inside in a small sheet. All labels are Arabic and building #09 is gone. The map is downloaded from the site (cached per version), so future map changes need no app update.
- **PDFs:** a smoother reader with pinch and double-tap zoom and a page bar; Download stays, Open is removed.
- **Edit subjects:** redesigned page with level filters and tiles. "Use device theme" is removed from the menu.
- **Sign-in:** student IDs and codes typed with Arabic digits work.
- **Over-the-air updates:** releases are built with Shorebird (`./shorebird.sh`), so later Dart/UI changes reach phones without a store update. Patches must be signed with the release key (see README).

## 2.4.0 (11) — not released on its own

Community materials (view, download, previews), community notices and subject choices; included in 2.5.0.

## 2.3.0 (10) — 2026-10-25

Choose your group; smoother schedule.
