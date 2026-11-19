# 07 — Visual polish backlog

**Type:** low-severity UI observations from the 1.0.1 screenshot review.
**Status:** open, mostly cosmetic.
**Device:** OPPO A38, 360 x 806 dp, Arabic and English.

These are separate from the critical dock bug in
[`01-bottom-navigation-floating.md`](./01-bottom-navigation-floating.md).
None of them block messaging; they are listed so the UI round can be
finished deliberately.

## Observed

### 1. Empty state icon sits under the dock

On Home with no peers, the inset Wi-Fi illustration and the "No one here
yet" copy end up behind the misplaced dock (fixed by 01). After the dock is
anchored correctly, check that the empty state is vertically centred in the
remaining space and not pushed down.

### 2. Settings content needs bottom breathing room

The accent swatches and the custom-colour row were covered by the dock
(fixed by 01). With the dock back at the bottom, `extendBody: true` still
lets the last rows scroll under it — add bottom padding of roughly the dock
height so the About section can scroll fully clear of the bar.

### 3. Home header "＋" is not an add button

See [`02-add-person-button-ux.md`](./02-add-person-button-ux.md). The
symbol promises a flow that does not exist yet.

### 4. Chat header eye and call button

See [`03-chat-header-controls.md`](./03-chat-header-controls.md). The eye
has no label, and the call button looks live while it only shows a
"next update" snackbar.

### 5. Arabic and English numerals

Arabic UI correctly shows Arabic-Indic digits in dates ("١٠ جمادى الآخرة
١٤٤٨") and times ("٠٢:٤١ م"), while message timestamps in the chat list use
Western digits ("Just now", "25 minutes ago" remain English when the app
language is English; the Arabic screenshot uses Arabic). Verify any new
string goes through `listTime()` / `format.dart` instead of raw
`DateTime.toString()`.

### 6. Status bar contrast

The app draws edge-to-edge under the status bar. On the dark neumorphic
background the clock and icons are white and readable, but confirm on a
light accent (for example yellow) that the system icon appearance is still
set to light. The current implementation looks correct on the screenshots.

## Checked and fine

- RTL mirroring of the dock works: chat on the right, settings on the left.
- Splash text and progress indicator render in both languages.
- Chat bubbles, avatars, and the safety-code screen keep the neumorphic
  depth treatment and readable contrast.
- Accent colour persists across restarts (Settings swatches and custom
  colour row behave as expected).
- System back closes the chat and returns to the correct tab.

## Suggested next pass

1. Ship the dock fix, re-screenshot Home and Settings in both languages.
2. Decide the "＋" behaviour (add-person sheet vs refresh control).
3. Give the visibility toggle an explicit label/sheet.
4. Either disable the call button with a "Soon" badge or hide it until the
   call feature lands.
5. Add a shared bottom padding constant used by every scrollable tab.
