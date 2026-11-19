# 06 — Device testing setup: adb, mobile-mcp, screenshots

**Type:** tooling notes.
**Status:** working on this machine (Arch Linux + OPPO A38).
**Purpose:** drive the real app on the owner's phone, capture screenshots, and
inspect the UI without an emulator.

## 1. adb

Installed from the Arch repositories:

```bash
sudo pacman -S android-tools
```

If pacman complains that the database is locked:

```bash
sudo rm /var/lib/pacman/db.lck
```

On the phone:

1. Settings → About device → tap **Build number** seven times.
2. Settings → System → Developer options → enable **USB debugging**.
3. Connect USB and choose **File transfer / MTP** (charging-only does not
   expose adb).
4. Accept the RSA fingerprint prompt.

Check:

```bash
adb devices
# VCKZYHRCAEKFHYCA	device
adb shell getprop ro.product.model
# CPH2579
```

Common failures seen here:

- `adb devices` empty while the phone only charges → change the USB mode and
  re-enable USB debugging.
- `unauthorized` → revoke USB debugging authorisations on the phone and
  re-accept the prompt.

## 2. mobile-mcp

The MCP server from <https://github.com/mobile-next/mobile-mcp> exposes the
phone as structured tools (list devices, launch app, read the accessibility
tree, tap by ref or coordinate, swipe, press buttons, save screenshots).

Install (global npm prefix is `~/.npm-global` on this machine):

```bash
npm install -g @mobilenext/mobile-mcp@latest
# binary: mcp-server-mobile
```

Register it in `~/.config/opencode/opencode.jsonc`:

```json
{
  "mcp": {
    "servers": {
      "mobile-mcp": {
        "type": "local",
        "command": ["npx", "-y", "@mobilenext/mobile-mcp@latest"]
      }
    }
  }
}
```

Restart OpenCode once so the tools appear as native MCP tools.

## 3. Using it without OpenCode (fallback bridge)

When the MCP tools are not loaded in the current session, `mcp_client.py`
(a tiny stdio JSON-RPC client kept outside the repo) can call the same
server:

```bash
python3 mcp_client.py list-tools
python3 mcp_client.py mobile_list_available_devices '{}'
python3 mcp_client.py mobile_launch_app \
  '{"device":"VCKZYHRCAEKFHYCA","packageName":"app.kinly.chat"}'
python3 mcp_client.py mobile_save_screenshot \
  '{"device":"VCKZYHRCAEKFHYCA","saveTo":"/path/shot.png"}'
python3 mcp_client.py mobile_list_elements_on_screen \
  '{"device":"VCKZYHRCAEKFHYCA","format":"json"}'
python3 mcp_client.py mobile_click_on_screen_at_coordinates \
  '{"device":"VCKZYHRCAEKFHYCA","x":240,"y":790}'
python3 mcp_client.py mobile_swipe_on_screen \
  '{"device":"VCKZYHRCAEKFHYCA","direction":"up","x":360,"y":1300,"distance":900}'
python3 mcp_client.py mobile_press_button \
  '{"device":"VCKZYHRCAEKFHYCA","button":"BACK"}'
```

## 4. Screenshot commands used

Raw adb (fastest, no MCP round-trip):

```bash
adb exec-out screencap -p > shot.png
```

Launch the app cleanly:

```bash
adb logcat -c
adb shell am force-stop app.kinly.chat
adb shell am start -n app.kinly.chat/.MainActivity
```

## 5. Pitfalls found

- **The phone locks itself.** `screencap` then returns a black frame
  (`ui-settings-about.png` was 7.8 KB and completely black). Check with:
  `adb shell dumpsys power | grep mWakefulness=` — if it says `Asleep`,
  wake and unlock first (`adb shell input keyevent KEYCODE_WAKEUP`).
- **MCP server startup cost.** `npx -y` resolves the package on every call
  (several seconds). Installing globally first makes repeated calls faster.
- **Coordinates are physical pixels.** The device is 720 x 1612 @ 320 dpi;
  Flutter's logical size is 360 x 806, so divide screenshot coordinates in
  half if you reason from the widget tree.
- **Flutter exposes little to uiautomator.** Only semantic labels and a few
  buttons show up. Everything else needs screenshot inspection or refs from
  `mobile_list_elements_on_screen`.
- **Screenshots contain personal data** (owner name, avatar, message list).
  They are excluded from git — see `.gitignore`.

## 6. Device used

| Field | Value |
|-------|-------|
| Model | OPPO A38 (CPH2579) |
| Android | 15 |
| Resolution | 720 x 1612 px |
| Density | 320 dpi (xhdpi, 360 x 806 dp) |
| App | `app.kinly.chat`, arm64, debug-signed |
