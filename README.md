# Humline

A compact now-playing widget for the Omarchy bar: a line of dots that hums
along with whatever is playing, and a themed card with cover, seek bar,
volume and jump-to-player. When the player is
[cliamp](https://github.com/bjarneo/cliamp) it also gets likes, playlists and
a source browser.

> **Unofficial, personal project.** I built Humline mainly for my own setup
> (Omarchy + cliamp) and share it as-is. It is not made, endorsed or
> supported by Omarchy, Basecamp, cliamp or any music service.

## Features

- **Bar:** a tiny 10-band dotted spectrum while audio plays (real PipeWire
  output via [cava](https://github.com/karlstav/cava)); a pause glyph when
  paused. Works with any MPRIS player: browsers, web apps, mpv, terminal
  players.
- **Card:** cover art, title/artist/album, larger spectrum, seek bar,
  previous/play/next, shuffle/repeat (if the player supports them), volume.
- **Jump to player:** focuses the window that is playing (browser, web app,
  terminal) or even the right [herdr](https://herdr.dev) tab. The mouse
  cursor stays put.
- **Several players at once:** each gets its own row with play/pause and
  jump; click a row to make it the main one.
- **cliamp extras** (only while cliamp is the active player):
  - **Heart**: like/unlike the track in cliamp's Favorites (same as `n` in
    cliamp).
  - **Add to playlist**: your local cliamp playlists (click a checked one to
    remove the track) and, on request, your own Spotify playlists.
  - **Browse**: one tab per cliamp provider (Radio, Local, Podcasts,
    Spotify…); pick a playlist or station to play it.

## Compatibility

Tested on Omarchy 4.0 (the Quickshell-based `omarchy-shell`, not the older
Waybar setup), Hyprland 0.56 and cliamp 2.0.1 and 2.2.0.

| Needs | For |
| --- | --- |
| `cava` | the spectrum (without it you get a static icon) |
| `jq`, `busctl` (systemd), `hyprctl` | jump to player |
| `python3` | the cliamp extras |
| `herdr` (optional) | jumping to a herdr tab |

## Install

```bash
omarchy pkg add cava jq
omarchy plugin add https://github.com/resn3t/humline.git --enable
```

It lands in the center of the bar; move it with
`omarchy bar move humline --section right`. Optional keybinding
(`~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + M", "Now playing", "omarchy-shell -q humline togglePopup")
```

**Update:** `omarchy plugin update humline` · **Remove:** `omarchy plugin remove humline`

## Usage

| Action | Result |
| --- | --- |
| Left-click | open/close the card (Esc closes it) |
| Right-click | jump to the player |
| Middle-click | play/pause |
| Scroll | previous/next track |
| Seek bar | drag, or scroll for ±10 s |
| Volume slider | drag, or scroll for ±5 % |

IPC for scripts and keybindings:

```bash
omarchy-shell humline togglePopup
omarchy-shell humline focusPlayer
omarchy-shell humline seek 10        # or: seek -10
omarchy-shell humline volume 0.05    # or: volume -0.05
# cliamp only:
omarchy-shell humline toggleFavorite
omarchy-shell humline browse
omarchy-shell humline browseSource radio   # or local, podcast, spotify…
omarchy-shell humline addToPlaylist
```

## Known limits

- **cliamp's heart marker:** cliamp has no remote command for favorites, so
  Humline writes `favorites.toml` itself, in cliamp's format and under its
  lock. cliamp's Favorites list picks it up right away, but the ♥ next to a
  track in a running cliamp only updates after cliamp restarts.
- **Spotify in cliamp:** the first Spotify list after starting cliamp can
  take 10–20 s, and cliamp doesn't respond meanwhile. That's why Spotify
  playlists only load when you ask for them. Spotify playlists are
  add-only, and adding twice adds the track twice.
- Shuffle/repeat changes are saved to cliamp's `config.toml`; that's
  cliamp's own behaviour.
- At cliamp's minimum volume (-30 dB), cliamp reports full volume over MPRIS,
  so the slider shows 100 % until you move it.
- Changes made in cliamp's own UI while the card is open show up on the next
  track change.
- In a normal browser, jumping focuses the right window but not the playing
  tab. Web apps (their own window) are fine.

## Notes

- Resource use: nothing extra runs while nothing is playing. cava runs
  while audio plays, and the cliamp parts only load while the card is open.
  Every cliamp action is one short-lived call.
- Like every Omarchy plugin, Humline runs unsandboxed inside your shell.
  Read the code before installing; it's short.
- Privacy: the only network request Humline makes itself is a Spotify oEmbed
  lookup for a cover when a player reports a `spotify:track:` without one.

## Legal

Free to use, modify and share under the [MIT License](LICENSE). The card
layout is adapted from Omarchy's built-in media widget (MIT, © David
Heinemeier Hansson). All product names and trademarks (Omarchy, cliamp,
Spotify, herdr, cava and others) belong to their respective owners. They are
named here only to describe compatibility. Provided "as is", without
warranty.
