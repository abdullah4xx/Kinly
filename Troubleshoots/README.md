# Kinly troubleshooting log

Device used for the screenshots: **OPPO A38 (CPH2579)**, Android 15,
720 x 1612 px, 320 dpi. App builds: **1.0.1+2** and later.

## Layout

```text
Troubleshoots/
├── README.md      this index
├── docs/          one Markdown file per ordinary issue, all in one place
├── screenshots/   screenshots for the issues in docs/
└── major/         one folder per large problem or major update
```

A large incident or a major release gets its own folder under `major/`,
with its own write-ups and screenshots, so it does not get lost among the
small fixes. Folders and file names are English; user-facing text inside
the documents can be Arabic or English.

Screenshots live in this repository folder but are **not committed**
(they show the owner's name, avatar, and chat list). See `.gitignore`.

## Ordinary issues (`docs/`)

| # | Problem | Severity | Status |
|---|---------|----------|--------|
| 01 | Bottom navigation dock floats in the middle of the screen and covers content | Critical | Fixed in source, verification pending |
| 02 | The "+" button on Home is labelled "Chats" and only refreshes | Medium | Open |
| 03 | Chat header visibility toggle is ambiguous; call button is a placeholder | Low | Open |
| 04 | How adb and mobile-mcp were set up for device testing | Tooling | Done |
| 05 | Visual polish backlog from the screenshot review | Low | Open |

## Major updates (`major/`)

| Version | Scope | Status |
|---------|-------|--------|
| [1.0.1 — startup hang and in-app updates](major/1.0.1-startup-hang-and-updates/README.md) | Splash no longer hangs; GitHub update checks | Shipped |

## Reproducing the screenshots

```bash
adb devices
adb shell am start -n app.kinly.chat/.MainActivity
adb exec-out screencap -p > shot.png
```

The `mobile-mcp` server was also used for `mobile_list_available_devices`,
`mobile_launch_app`, `mobile_list_elements_on_screen`, and
`mobile_save_screenshot`. See
[`docs/04-device-testing-setup.md`](docs/04-device-testing-setup.md).
