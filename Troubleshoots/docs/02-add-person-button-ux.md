# 03 — Home "+" button is mislabelled and only refreshes

**Severity:** medium (confusing first-run action).
**Status:** open — needs a product decision.
**Observed on:** 1.0.1+2, Home (English and Arabic).

## Symptoms

- The top corner of Home shows a large accent "+" button.
- Its accessibility/tooltip label is `strings.get('chats')` ("Chats"), not
  "Add" or "Refresh". `mobile_list_elements_on_screen` reported the button
  as `الدردشات` (Chats).
- Tapping it does not add a person or open a sheet. It calls
  `controller.refresh()` and then shows a snackbar containing either the
  "no people" sentence or a bare number (`0`, `2`, ...).

Current code in `app/lib/screens/home.dart`:

```dart
NeuIconButton(
  icon: Icons.add_rounded,
  tooltip: strings.get('chats'),
  onPressed: () async {
    await controller.refresh();
    ...
    SnackBar(content: Text(controller.people.isEmpty
        ? strings.get('noPeople')
        : '${controller.people.length}'))
  },
)
```

## Why it matters

- A "+" is the universal affordance for adding a person/chat. Users tap it
  expecting a flow and get a snackbar with a number.
- Screen readers announce "Chats", which is wrong for the action.
- `noPeople` is a full sentence, while the non-empty case is just a count;
  the two states do not read as the same feature.

## Suggested fix (pick one)

1. **Keep "+" as add person:** open a bottom sheet with the options that
   actually exist today (retry discovery, show the local address/QR, manual
   address entry). Label it `addPerson` in both languages.
2. **Make it a refresh control:** use `Icons.refresh_rounded`, label it
   `refresh`, and show a snackbar with a proper message such as
   "Searching for people..." followed by "N people found" / "No one found".

Until one is chosen, at minimum change the tooltip to a truthful label and
make the snackbar use a shared `peopleFound` string with the count.
