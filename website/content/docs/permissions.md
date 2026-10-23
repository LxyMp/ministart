---
title: Permissions
description: What Tinycast asks for, why it needs it, and when it asks.
---

Tinycast asks for a permission **only when you use a feature that needs it**, never at launch. The
launcher, calculator, emoji picker and search all work without any permissions.

**Settings → Permissions** shows the status of Accessibility, and opens the right
System Settings pane for you.

## Accessibility

macOS describes this permission as "control your computer". Tinycast uses it to read from and write
to the window you were using before the palette opened.

Grant it in **System Settings → Privacy & Security → Accessibility**, or from
**Settings → Permissions**.

### What needs it

| Feature                                                                       | Why                                                    |
| ----------------------------------------------------------------------------- | ------------------------------------------------------ |
| [Clipboard](/docs/features/clipboard) and [emoji](/docs/features/emoji) paste | Puts the item into the app you were using              |
| [Snippets](/docs/features/snippets)                                           | Detects the keyword you type, then inserts the text    |
| [Hyper key](/docs/reference/hotkeys#hyper-key)                                | Turns one physical key into a modifier chord           |
| Double-tap modifier shortcuts                                                 | Detects the tap pattern                                |
| <kbd>⌘</kbd><kbd>esc</kbd> back to the root search                            | macOS uses this shortcut unless Tinycast intercepts it |
| `getSelectedText` in [extensions](/docs/extensions)                           | Reads the selection from the frontmost app             |

### Snippets and keystroke matching

Snippet keyword expansion is the only feature that reads what you type, so these are the rules it
follows:

- Snippets are **off** by default. Turning them on shows an explanation first, and turning on the
  switch counts as your consent. There's no separate prompt.
- Matching happens **only on your Mac**. Keystrokes are never stored or sent anywhere.
- The typing buffer holds at most 256 characters. It resets when you switch apps, press a shortcut
  with a modifier, turn on Secure Event Input, or stop typing for 15 seconds.
- Tinycast uses a **listen-only** event tap under the Accessibility permission. It doesn't use Input
  Monitoring.
- **Restoring a settings backup can't turn snippets on**, so importing a file someone sent you can
  never enable keystroke listening.


## Camera

**Open Camera** asks for camera access the first
time you use them. The camera isn't used before then, and it turns off as soon as the preview closes.

## Automation and Bluetooth

A few actions show their own macOS prompt the first time you run them:

- **Show Info in Finder** in the [uninstaller](/docs/launcher/uninstall), and some
  [system actions](/docs/launcher/system-actions), control other apps through Apple Events, which
  shows the standard Automation prompt.
- **Toggle Bluetooth** shows the Bluetooth prompt.

If you decline, Tinycast tells you and links to the right System Settings pane, so the action never
fails silently.

## Full Disk Access

Tinycast **checks** whether it has Full Disk Access but **never asks** for it automatically.
Settings → Permissions and Settings → File Search both show its status and offer a button to open
System Settings → Privacy & Security → Full Disk Access, where you can grant it manually.

[File Search](/docs/features/file-search) requires this access to build its private index on your Mac.
For uninstalling apps, it is optional.

The [uninstaller](/docs/launcher/uninstall) checks in the background to work out which files it can
move. Without Full Disk Access, protected folders like `~/Library/Containers`,
`~/Library/Group Containers` and `~/Library/Cookies` appear as locked rows. At worst, you remove
those by hand.

## What Tinycast never needs

- **Screen Recording.** The window switcher reads window titles through Accessibility.
- **Location.** The calculator picks your currency from your Mac's region setting.
- **Input Monitoring.** Snippets listen through Accessibility, as described above.
