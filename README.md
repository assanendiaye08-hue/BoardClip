<div align="center">

# BoardClip

**A clipboard manager for macOS, on glass.**

A fast, native, Liquid-Glass clipboard history that lives in your menu bar.
Press **⌘⌥V**, pick a clip, and it pastes straight into whatever you were typing.

</div>

---

## Features

- **Top-of-screen glass HUD** — summon with **⌘⌥V**, recency-ordered, click (or **⌘1–9**) to paste into the focused field, then it gets out of the way.
- **Direct quick paste** — press **⌘⌥1–9** to paste one of the nine newest clips without opening the HUD.
- **Everything you copy** — text, rich text, links, colors, images, and files, each with its own preview. Drag image clips straight into upload boxes or other apps.
- **Screenshots, automatically** — ⌘⇧4 file screenshots are pulled in from your screenshot folder, not just clipboard ones.
- **Spaces** — durable boards to keep clips forever, separate from the rolling history.
- **Smart actions** — Save image → Photos, Research a clip on the web, Reveal files in Finder, and Transform & Paste (UPPERCASE, slugify, join lines…).
- **Fuzzy search** — just start typing.
- **Privacy-first** — skips password-manager clips (concealed/transient), plus a per-app exclusion list.
- **Auto-clean** — keeps a configurable window of history; pinned and Space-saved clips never expire.
- **Auto-updates** — ships with [Sparkle](https://sparkle-project.org); new versions install themselves.
- **Native & light** — SwiftUI + AppKit, menu-bar agent (no Dock icon), launches at login.

## Install

1. Download `BoardClip-x.y.z.dmg` from the [Releases](../../releases) page.
2. Open it and drag **BoardClip** to **Applications**.
3. First launch: **right-click → Open** (the app is signed but not notarized, so Gatekeeper asks once).
4. In the welcome window, enable **Accessibility** so BoardClip can paste for you (without it, clips are still copied — just press ⌘V yourself).

## Shortcuts

| Key | Action |
|---|---|
| **⌘⌥V** | Open the clipboard bar (rebindable in Settings) |
| **⌘⌥1 – ⌘⌥9** | Directly paste the Nth newest clip without opening the bar |
| **⌘1 – ⌘9** | Paste the Nth clip while the bar is open |
| **↩** | Paste the selected clip |
| **⌥** + click/↩ | Paste as plain text |
| **esc** | Close the bar |
| Right-click a clip | Pin, add to Space, transform, save to Photos, research… |

## Build from source

Requires macOS 26+ and Xcode 26+.

```sh
make run          # build, bundle, and launch
make release      # release build → build/BoardClip.app
make dmg          # build a distributable DMG
make cert         # (once) create a stable self-signed identity so permissions persist across rebuilds
Scripts/export-codesign-secret.sh
                  # (once) upload that identity to GitHub Actions so updates keep Accessibility permission
```

The app builds with Swift Package Manager and is assembled into a `.app` by `Scripts/bundle.sh`
(which embeds and signs `Sparkle.framework`).

## Releasing

1. **One-time:** create and upload a stable code-signing identity:
   ```sh
   make cert
   Scripts/export-codesign-secret.sh
   ```
   This keeps macOS Accessibility permission stable across updates. Without it, releases fall back
   to ad-hoc signing and macOS may make users remove/re-add BoardClip in Accessibility settings.
2. **One-time:** `Scripts/sign-update.sh keygen` → put the printed `SUPublicEDKey` into
   `Resources/Info.plist`, set `SUFeedURL` to your repo's `releases/latest/download/appcast.xml`,
   and edit `AppInfo.githubRepo`. Export the private key and add it to the repo secret
   `SPARKLE_ED_PRIVATE_KEY`.
3. **Each release:** bump `AppInfo.version`, then:
   ```sh
   git tag v0.2.0 && git push --tags
   ```
   GitHub Actions (`.github/workflows/release.yml`) builds the DMG, signs the appcast, and
   publishes the release. Installed copies update themselves via Sparkle.

To get a Gatekeeper-clean first launch later, add a paid Apple Developer ID and enable the
(commented) notarization step in the workflow.

## Privacy

BoardClip is **non-sandboxed** and stores clipboard history **locally** at
`~/Library/Application Support/BoardClip/`. Update checks contact GitHub, and the explicit
**Search Google for Clip** action sends the selected clip text to Google. It needs **Accessibility**
to paste and, when you use Save to Photos, **Photos** add access.

## License

MIT — see `LICENSE`.
