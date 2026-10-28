# Tab sidebar (fork feature)

A vertical tab sidebar for the macOS app, built from the Claude Design spec in the project
"Vertical Tab Sidebar UX Design" (claude.ai/design/p/d9442579-5609-44e0-a983-ff99d216f8de; files
`sidebar-prototype.html`, `artboards.html`, `motion-and-assets.html`). Code: `macos/Sources/Features/TabSidebar/`.
The native tab bar is hidden while the sidebar is on (use `macos-titlebar-style = transparent` or `native`).

## What it does
- **View as:** Panes (one row per split, under its tab's name) or Tabs (one row per tab; *Tab item* =
  Focused session or Summary). **Density:** Compact or Expanded. **Pane title as** command / conversation,
  working directory or branch; **Additional metadata** fills in the rest (the one used as title is left out).
- **Search** (case-insensitive substring) over names, titles, directories, branches and groups.
- **Groups** are containers with a color, rail, collapse, rename, pin and ungroup.
- **Pinned** area for tabs and groups.
- **Drag and drop** with the spec's outcome table: 4 pt threshold, ghost, auto-scroll, 600 ms spring-load
  of collapsed groups, Esc cancels. Group drags move the whole group.
- **Hover card** (600 ms dwell, 150 ms grace), **view options panel**, context menus with the swatch row.
- **Keyboard:** the list has a focus cursor separate from selection. Arrows move it, Space selects,
  ⌥↑/⌥↓ move, ⌥←/⌥→ leave or join a group, ↩/F2 rename, ⌘⌫ close, typing starts a search.
- **Colors** are derived from the terminal background (dark and light), 152 values checked against the spec.
- **Saved with window restoration:** pins, groups, names, colors.

## Added in the second round (Claude Design parts A, B and C)
- **Custom top bar** replaces the macOS title bar (`TabSidebarTopBar.swift`): 38 pt, traffic lights, the sidebar
  toggle at x = 78, the tab title and directory in the middle, New Tab (right-click for the full menu),
  Split and View Options on the right. Dragging it moves the window, double-click zooms. Works with
  `macos-titlebar-style = transparent` and `native`; the hidden and tabs styles keep their own title bars.
- **Pointer handling is AppKit** (`TabSidebarPointer.swift`): rows and headers are invisible "surfaces", the
  sidebar's host view runs one press / drag / click / hover state machine. Fixes hover inside groups and drags.
- **Compact vs Relaxed**: Compact is one 28 pt line with a branch chip; Relaxed is 52 pt with a 28 pt tile,
  branch + diff and directory lines, rows 8 pt apart.
- **Pinned**: a "Pinned N" header over a tinted container, a hairline and an "Open tabs N" header; pinned rows
  show a pin glyph and an Unpin button instead of Close. Any number of tabs and groups can be pinned.
- **Hide / show**: the top bar toggle (⌘\). While hidden, hovering the 6 pt left edge for 120 ms slides the
  sidebar in over the terminal; leaving closes it after 300 ms, Esc closes it at once.
- **Row actions**: loose rows show More + Close, rows in a group only Close, group headers More + Close
  (closing asks first). The pane menu has Maximize / Restore, Minimize, Move Pane to…, Split, Close Other Panes.
- **Panes** cannot be dragged narrower than 220 pt or shorter than 120 pt; a maximized pane shows a banner.

## Third round (Claude Design part D)
- **Three block types**, the same in Open tabs and Pinned: a single tab is one plain row (a named single tab uses its
  name as the row title); a multi-pane tab has a header (chevron, split icon, name, pane count) with its panes indented
  under a guide line; a group is a tinted container with a stack icon, name, count pill and chevron (grey and railless
  when it has no color). Hairlines between blocks are gone.
- **Collapse**: the group chevron is always visible; multi-pane tab headers fold their panes; "Pinned" and "Open tabs"
  fold (per window, not saved across relaunch; a drag opens them while it lasts).
- **Color swatches** are an AppKit view with hover, pressed and selected states; the ring moves to the new color and
  the menu closes 200 ms after the click.
- **Pane controls**: hovering a terminal pane for 150 ms shows More and Close at its top right. A single pane shows them
  only with "Pane controls on single panes" on in View Options.
- **Relaxed** is 44 pt (56 pt with a detail line), 26 pt tile, rows 6 pt apart: the first Relaxed, trimmed by about 15%.

## Deviations from the spec
- Not built: Warp-cloud items (Share Session, Cloud Agent, New Worktree Config) and the generic "New Tab".
  "Agent" launches `claude`.
- Pane statuses error / cancelled / blocked and the unread dot cannot be detected; only done (✳) and
  working (braille spinner in the title).
- Options panel, sidebar width and visibility are global, not per window.
- Drag ghost glide-back and settle glide are not animated: the drop commits instantly with a 400 ms settle flash.
- Menus open at the cursor. Minimize puts another pane in front instead of drawing a 28 pt strip, and the
  divider stops at the limit without the resistance animation. The 48 pt rail variant is not built.

## Tab configs
`~/.config/ghostty/tab-configs.json`: `[{"name": "api", "directory": "~/dev/api", "command": "npm run dev"}]`.

## Efficiency
- No timers or polling: refreshes are event-driven, coalesced, capped at 4 per second, skipped while the
  window is hidden, and only published when the snapshot changed.
- Sidebar hidden = the SwiftUI view does not exist.
- Opaque theme-colored background, no vibrancy; git branch read from `.git/HEAD` (no subprocess).
- The hover card and options panel are non-activating panels and never take focus from the terminal.

## Keys
| Action | Shortcut |
| --- | --- |
| Toggle tab sidebar | ⌘\ |
| Search tabs | ⇧⌘A |
| Reopen closed tab | ⇧⌘T |

## Tests
`macos/Tests/Features/TabSidebar/`: layout and row rules, drag/drop and pin/group operations, hit-test
geometry, and the palette against the spec's resolved colors.
