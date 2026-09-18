# Humline Player roadmap

Positioning: a tiny, sleek now-playing line for the Omarchy bar. Generic
MPRIS by default, cliamp-native when the player is cliamp. Every feature has
to earn its bytes: Humline stays small and needs no new runtime dependencies.

## Guardrails (must hold in every release)

- Nothing runs while paused; one `cava` while playing.
- Opening the card costs about 10 MB of shell memory or less and gives it
  back on close.
- No new runtime dependencies beyond `cava`, `jq`, `python3` and the system
  tools already used.
- No network calls beyond the existing cover lookup and cliamp's own bridge.

## 2.0 must-have

- ~~Footprint script and a side-by-side with the built-in widget~~ done in
  1.2.0 / 1.3.0 (see the README table); other third-party widgets not measured.
- ~~Keyboard use of the card~~ done in 1.2.0 (Omarchy's `KeyboardPanel`).
- ~~One `cava` per monitor~~ done in 1.3.0: one shared cava (tested on two monitors).
- Listing in the Omarchy plugin marketplace, tagged releases with notes.
- Decide the plugin id policy (`humline` today; a namespaced id would break
  existing installs and bar placement).

## 2.0 nice-to-have

- Adapt to crowded bars (shrink, then hide the spectrum) instead of a fixed
  width.
- ~~Tiny settings: hide when paused, dot count~~ done in 1.2.0.
- Ignore noise players (notification sounds, games).
- Use `cliamp visstream` for cliamp so cava becomes optional there: on cliamp
  2.2.0 it only returned zero bands while playing, so it was dropped for now.
- Gate the spectrum on a matching PipeWire stream: cava reads the whole
  output, so this cannot make dots per-player and risks blanking them.
- Refresh cliamp's heart marker live if cliamp gains a remote favorites
  command.
- Vertical bar support.

## Out of scope (to stay tiny)

- Lyrics, a full settings panel, non-MPRIS backends, Waybar support, a
  music-service client beyond the existing cliamp bridge.
