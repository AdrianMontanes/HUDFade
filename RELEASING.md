# Releasing HUD Fade

Releases are automatic. `.github/workflows/release.yml` uses the
[BigWigs packager](https://github.com/BigWigsMods/packager) to build `HUDFade-<version>.zip` and upload it to
GitHub Releases, CurseForge, Wago and WoWInterface. A site is skipped if its token secret is missing.

It runs when a push to `main` changes `HUDFade.toc` to a version that has no release yet (it tags that commit
itself if needed), or when a version tag is pushed by hand.

## Steps

1. Set `## Version:` in `HUDFade.toc` to the new version, for example `1.2.0`.
2. Add a section for it at the top of `CHANGELOG.md`. That text becomes the changelog on every site.
3. Run the tests and the linter: `lua5.1 tests/mock.lua .` and `luacheck .` (both also run on every push).
4. Commit and push to `main`. Only push a new version once it has been tested in game: the push is the release.
5. Watch the Release run under the repo's Actions tab (about two minutes).

Tags with `alpha` or `beta` in them (like `0.3.0-beta1`) are uploaded as alpha or beta files, which the
CurseForge app only offers to people who opted in.

## One-time setup

- Repo secrets (Settings > Secrets and variables > Actions): `CF_API_KEY`, `WAGO_API_TOKEN`, `WOWI_API_TOKEN`.
- Project IDs in `HUDFade.toc`: `## X-Curse-Project-ID`, `## X-Wago-ID`, `## X-WoWI-ID`.
- A version released before the Wago project existed can be sent there with the Upload to Wago workflow (Actions
  tab > Upload to Wago > Run workflow). It uploads to Wago only.

## Libraries

The minimap button uses LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0. They are not in the
repo: the packager downloads them into `Libs/` (listed under `externals` in `.pkgmeta`). To run the addon straight
from a clone, copy those four folders into `Libs/` from any addon that ships them. Without them everything else
works, just with no minimap button.

## Game versions

The `## Interface:` line lists the Retail 12.x builds and `16001` for WoW Forever. The packager reads it and
tags each upload with the matching game versions, so one zip covers both clients. Add the new number there
when a patch changes the interface version.
