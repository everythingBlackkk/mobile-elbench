# Changelog

The ElBench app for Android and iOS. Server changes are listed in the backend's changelog
([everythingBlackkk/myFamily](https://github.com/everythingBlackkk/myFamily/blob/main/CHANGELOG.md)).

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
