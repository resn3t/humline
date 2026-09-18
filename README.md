# nowpip

A compact now-playing widget for the Omarchy bar: a live dot-spectrum while
music plays, and a themed card with cover, seek bar, volume and
jump-to-player on click.

> **Unofficial.** nowpip is a community plugin. It is not made, endorsed or
> supported by Omarchy, Basecamp, or any music service or player.

## Features

- **Bar:** a tiny 10-band dotted spectrum while playing (real audio via
  [cava](https://github.com/karlstav/cava)); a pause glyph when paused.
- **Card:** cover art, title/artist/album, larger spectrum, seek bar with
  elapsed/total time, previous/play/next, volume slider.
- **Jump to player:** focuses the window that is playing: browser/web app,
  terminal app, or even the right [herdr](https://herdr.dev) tab. Your mouse
  cursor stays where it was.
- **Multiple sources:** every active player is listed with its own
  play/pause and jump buttons. Click a row to make it the main one.
- **Shuffle/repeat** toggles for players that support them.
- **cliamp extras** when [cliamp](https://github.com/bjarneo/cliamp) is the
  active player: like button, add to playlist, and a source browser (see
  below).
- **Cover fallback:** if a player reports a `spotify:track:` URI but no
  cover, the thumbnail is fetched from the public Spotify oEmbed endpoint.
- Uses your Omarchy theme colors and the shell's own controls.

## Compatibility

Tested on Omarchy 4.0.4 (Quickshell-based `omarchy-shell`) with Hyprland
0.56. Works with any MPRIS player (browsers, web apps, mpv, terminal
players, desktop clients…). Older Omarchy versions without the Quickshell
shell (Waybar-era) are **not** supported.

| Dependency | Needed for |
| --- | --- |
| `cava` | the spectrum (without it you get a static icon) |
| `jq`, `busctl` (systemd), `hyprctl` | jump to player |
| `herdr` (optional) | jumping to a herdr tab |
| `cliamp` 2.x, `jq`, `flock` (optional) | the cliamp extras |

## Install

```bash
omarchy pkg add cava jq
omarchy plugin add https://github.com/resn3t/nowpip.git --enable
```

This places nowpip in the center of the bar. To move it:
`omarchy bar move nowpip --section right`.

Optional keybinding for the card (add it to `~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + M", "Now playing", "omarchy-shell -q nowpip togglePopup")
```

**Update:** `omarchy plugin update nowpip` · **Remove:** `omarchy plugin remove nowpip`

## Usage

| Action | Result |
| --- | --- |
| Left-click | open/close the card |
| Right-click | jump to the player |
| Middle-click | play/pause |
| Scroll | previous/next track |
| Drag/scroll the seek bar | seek (scroll = ±10 s) |
| Scroll the volume slider | ±5 % |

IPC for scripts and keybindings:

```bash
omarchy-shell nowpip togglePopup
omarchy-shell nowpip focusPlayer
omarchy-shell nowpip seek 10     # or: seek -10
# cliamp only:
omarchy-shell nowpip toggleFavorite
omarchy-shell nowpip browse
omarchy-shell nowpip browseSource radio   # or local, spotify, …
omarchy-shell nowpip addToPlaylist
```

## cliamp integration

When cliamp is the active player the card gets a small extra row, and
shuffle/repeat go through cliamp (it doesn't expose them over MPRIS):

- **Heart:** adds/removes the track in cliamp's Favorites. cliamp has no
  remote command for this, so nowpip writes `favorites.toml` itself, in
  cliamp's own format and under its lock file (`favorites.toml.lock`).
- **Add to playlist:** your local cliamp playlists (with a check mark if the
  track is already in one; click again to remove it) and your own Spotify
  playlists. cliamp can only *add* to Spotify playlists, not remove.
- **Browse:** one tab per configured provider (`provider.list`), 20 items
  per page; click a playlist or station to load and play it in cliamp.

Everything cliamp-specific only exists while the card is open: no polling,
no event stream, just one short `cliamp remote call` per click (via
`bin/nowpip-cliamp`). Other players keep the plain MPRIS card.

## Notes

- Volume and seeking only appear if the player supports them over MPRIS.
  Live streams have no length, so they don't get a seek bar.
- In a normal browser, jumping focuses the right window but can't switch
  to the playing tab. Web apps (their own window) are fine.
- Like every Omarchy plugin, nowpip runs unsandboxed inside your shell.
  Read the code before installing; it's short.
- Privacy: the only network request nowpip makes itself is the optional
  Spotify oEmbed cover lookup described above (cliamp's own requests are
  cliamp's).

## Legal

Free to use, modify and share under the [MIT License](LICENSE). The popup
layout is adapted from Omarchy's built-in media widget (MIT, © David
Heinemeier Hansson). All product names and trademarks (Omarchy, Spotify,
herdr, cava, cliamp and others) belong to their respective owners. They are named
here only to describe compatibility. Provided "as is", without warranty.
