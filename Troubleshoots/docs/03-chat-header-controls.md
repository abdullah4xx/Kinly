# 04 — Chat header controls are ambiguous

**Severity:** low (does not block messaging).
**Status:** open.
**Observed on:** 1.0.1+2, chat with a peer (`../screenshots/04-chat-arabic.png`).

## Symptoms

- Next to the peer name there is a plain eye icon inside a dark circle. It
  toggles "show me to this person" but has no visible label and no state
  text. In Arabic the tooltip is only "visibility" / "hidden".
- The accent call button is enabled, but tapping it shows the snackbar
  "Calls arrive in the next update". A control that looks live but explains
  it is not implemented is misleading.

## Why it matters

- The eye can be read as "read receipts", "show profile", or "watch".
  Accidentally hiding yourself from a family member is a privacy action and
  should be explicit.
- A dead call button creates a bad first impression during testing.

## Suggested fix

1. Replace the eye with an icon plus a short label, or open a small
   confirmation/selection sheet: "Show me to Abdullah" / "Hide me from
   Abdullah".
2. Disable and dim the call button until calls exist, with a "Soon" badge,
   or hide it entirely. Keep `callsSoon` only if the button is visibly
   disabled.
3. Keep the avatar/name tap as the path to the safety-code screen; that part
   already works.
