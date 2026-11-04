# Changelog

The ElBench app for Android and iOS. Server changes are listed in the backend's changelog
([everythingBlackkk/myFamily](https://github.com/everythingBlackkk/myFamily/blob/main/CHANGELOG.md)).

## Over-the-air patch — 2026-11-04 (a photo in posts)

Shorebird patch 3 for Android 5.1.0 (Shorebird is Android-only). Needs backend v8.19.0 or later. iPhones get this with the next App Store build.

- **A photo in posts:** a photo button beside the character count in the post composer, drawn like the comment sticker button (same 24 px line icon and 36 × 44 tap area). It opens the system photo picker for one photo and turns off once a photo is added; remove it to choose another. A post can be just a photo. Editing a post shows its photo with a remove button, and can replace it.
- **Checked before upload:** GIF, SVG and anything that is not a PNG, JPG, WebP or iPhone (HEIC) photo is refused by its contents, not its name. Photos over 10 MB are refused too. The server checks again.
- **Small, quick uploads:** the system picker scales and re-encodes the photo natively to 2048 px (JPEG, quality 85) before upload, so a 12 MB iPhone HEIC photo leaves the phone as a few hundred kilobytes. Uploads show a progress bar and do not hold up other requests.
- **Smooth feed:** the photo's box has its final size before the photo arrives, painted in the photo's average colour. It is decoded at the box's size in device pixels rather than full size, keeps its own paint layer, and fades in once. Scrolling back shows it at once from memory, and a disk cache keeps it across launches. Signed links change every 12 hours, but the app caches photos by a stable key, so it does not download them again. The image cache now holds up to 160 MB.
- **Full-screen viewer:** tap the photo to view it full screen. Pinch or double-tap to zoom, and swipe down or tap close to leave. The feed copy shows at once, then the 2048 px copy replaces it.
- **Who can add photos:** the photo button shows only when the server allows it (`can_post_images`); a Super Admin can limit photos to verified members (blue, gold or Dr badge).
- **Profile:** posts in a profile's activity show a small thumbnail that opens the viewer.
- **Shorebird:** Dart-only change. It uses the `image_picker` plugin already in the release; no new packages, assets, permissions or native code.

## Over-the-air patch — 2026-11-03 (uploads)

Shorebird patch 2 for Android 5.1.0 and patch 3 for Android 5.0.0. No backend change.

- **Uploads no longer freeze the app:** a file upload (study material, profile picture, banner, admin image) starts in turn but no longer holds back other requests while it sends. Opening pages, refreshing, reacting and commenting work during a long upload instead of waiting for it to finish (measured: a page load during a 3 s upload took 3 s before, about 50 ms now). Sign-in, sign-out and other writes still run strictly in order.

## Over-the-air patch — 2026-11-03

Shorebird patch 1 for Android 5.1.0 and patch 2 for Android 5.0.0. No backend change.

- **Smooth PDF reading:** pages are drawn on a background thread as screen-sized images, visible pages first, then the next ones; pages scrolled past are skipped and only a few stay in memory. Large scanned PDFs no longer freeze scrolling while they load (measured on a 30 MB, 300 dpi PDF: time the app was unresponsive dropped from about 3 s to 0.2 s per 15 s of scrolling). Zooming in renders a sharper copy of the pages on screen.
- **Download progress:** the progress bar updates once per percent instead of on every received chunk.
- **Smarter material cache (up to 400 MB):** materials opened at least twice in the last 14 days are kept longest; one-off files go first, least recently opened first, so opening many PDFs in a row no longer pushes out the ones used for class. Room is made before each download, files unopened for 30 days and abandoned partial downloads are removed, and the file being read is never deleted.

## 5.1.0 (21) — 2026-11-03

Needs backend v8.17.0 or later.

- **See who reacted:** tapping the reaction count on a post, comment or forum answer opens a sheet listing everyone who reacted, with their picture, name and reaction. Tabs filter by reaction (All, 👍, ❤️, 😂); your own reaction is marked "(You)"; tapping a person opens their profile. People load only when the sheet opens, 30 at a time.
- **Comment reactions:** comments show the reactions used next to the count, like posts.
- **Over the air:** Android 5.0.0 already received these changes as Shorebird patch 1.

## 5.0.0 (20) — 2026-10-26

Needs backend v8.12.0 or later.

- **One-time class cancellation:** a cancelled class shows "Cancelled" (red) instead of its countdown on the schedule, the next-class cards and the Home schedule card; in the day's timeline it is marked Cancelled, faded and struck through. Only that one occurrence is affected; the following weeks show as usual, and the class returns to normal on its own once the cancelled date has passed.
- **Schedule admin:** admins with schedule permission get "Cancel next" on each class, with a confirmation naming the exact day, and "Restore" while a cancellation is pending.

## 4.5.0 (19) — 2026-10-26

- **Photo uploads:** the Upload Images button displays the photo icon consistently in community upload controls.
- **Upload progress:** files and images show a real byte-based progress bar and percentage, with a finishing state while the server completes the request and clean reset after completion or failure.
- **File viewing:** the bottom navigation is hidden while a material is open and restored when returning to the file list.

## 4.0.0 (18) — 2026-10-26

- **Home search:** displays only community posts as soon as typing starts, with a clear-search control and no stale results while a new search loads.
- **Keyboard:** tapping outside an input dismisses the keyboard throughout Android and iOS, including dialogs and bottom sheets.
- **Previous results:** quiz history uses clearer cards with aligned scores, time, status and date, responsive layouts and a full-width result action in light/dark themes and Arabic.
- **Loading:** each page family has a skeleton shaped like its content, with a shared lightweight animation that respects reduced motion.
- **Builds:** Android retains Shorebird; iOS continues to use standard Flutter without Shorebird. These UI improvements need no backend deployment.

## 3.5.0 (17) — 2026-10-25

- **Updates and notifications:** community updates show the sender's picture. Sender pictures open that person's profile while the notification itself still opens its post, comment, question or message. Anonymous senders stay private.
- **Toasts:** in-app messages use one rounded light/dark popup that slides up from the bottom and disappears after about two seconds.
- **Community uploads:** separate Upload Files and Upload Images buttons open the file picker and photo gallery respectively.
- **Reports:** the matching backend update separates report limits from ordinary mobile requests, fixing false “Too many attempts” errors while keeping abuse protection.
- **Profile editing:** avatar and banner camera controls open Photos directly; student ID, name and gender are hidden from the editor.
- **Shared links:** Android App Links and app navigation preserve shared destinations through sign-in. iOS includes link handling and optional Universal Links configuration; HTTPS Universal Links require an Apple Developer team with Associated Domains support.

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
