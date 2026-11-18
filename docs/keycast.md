# Keycast

[← Overview](../README.md)

`keycast.lua` displays keystrokes in a temporary overlay. It starts off by default; press **⌃⌥⌘K** to toggle it. A single status panel appears at the center of the pointer’s screen, updates in place when toggled repeatedly, and fades out after one second. Keycast does not record input. Configure it in `init.local.lua` before reloading; examples are in `init.local.example.lua`.

For a screen-corner overlay with physical key labels and repeat badges, add this to `init.local.lua`:

```lua
modules.keycast.config.enabled = true
modules.keycast.config.target = "mouseScreen"
modules.keycast.config.position = "bottomLeft"
modules.keycast.config.types = { shortcuts = true, text = true, special = true, mouse = false }
modules.keycast.config.showModifiers = true
modules.keycast.config.repeatMode = "badge"
```

The watcher reloads the configuration when the file is saved. The default text sequence interval is 0.5 seconds; each line remains for 2 seconds and fades over 0.2 seconds. A new line appears below older lines, which move upward.

- `target`: `focused` anchors to the focused window, `mouse` to the frontmost standard window under the pointer, and `mouseScreen` to the pointer's screen without following a window. If no window is found, the pointer's screen is used. The `mouse` window mode may miss accessory apps and nonstandard panels.
- `position`: `bottomLeft`, `bottomRight`, `topLeft`, `topRight`, or `center`; `margin` controls the inset in points. The overlay is clamped to the visible screen.
- `showModifiers = true` displays held ⌃, ⌥, ⇧, ⌘ and fn keys together, updating on press and release. When another key is pressed, the modifier indicator disappears and stays hidden until all modifiers are released. It has its own row and is off by default. Caps Lock is excluded because it is a toggle.
- `types`: independently enable `shortcuts` (⌘/⌥/⌃ combinations), `text`, `special` (navigation, function keys, space, etc.), and `mouse`. Shift-only characters count as text.
- When `text` is enabled, printable keys accumulate until `sequenceDelay` seconds of inactivity or another displayed action; a shortcut also clears the sequence when shortcuts are filtered out. A space or punctuation ends the line after being appended; older lines move up and fade after `linger`. Space appears as ␣. Long sequences keep their most recent characters visible and retain at most `maxTextLength` Unicode code points.
- Ordinary keys use US ANSI key positions, independent of the input method. Unmapped keys are omitted; displayed symbols do not represent the final IME composition. Shortcuts use the base key symbol with their modifier symbols.
- `repeatMode = "badge"` groups consecutive identical characters or actions within `sequenceDelay`, showing a superscript count (e.g. `a³`, `⌫³`). The default `"normal"` displays every input separately.
- `hotkey`, `colors`, `fontSize`, `sequenceDelay`, `linger`, `fadeDuration`, `moveDuration`, `maxRows`, `repeatMode`, `maxTextLength`, and startup `enabled` are configurable. Set `hotkey = nil` to omit the binding.

The overlay joins Spaces and supports full-screen windows. macOS Secure Input prevents keyboard events from reaching Hammerspoon. Text shows key events, not necessarily the final text committed by an input method; enabling text can expose sensitive input during screen sharing.
