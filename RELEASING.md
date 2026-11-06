# Releasing HUD Fade

Releases are automatic. Pushing a version tag runs `.github/workflows/release.yml`, which uses the
[BigWigs packager](https://github.com/BigWigsMods/packager) to build `HUDFade-<version>.zip` and upload it to
GitHub Releases, CurseForge, Wago and WoWInterface. A site is skipped if its token secret is missing.

## Steps

1. Set `## Version:` in `HUDFade.toc` to the new version, for example `0.3.0`.
2. Add a section for it at the top of `CHANGELOG.md`. That text becomes the changelog on every site.
3. Run the tests: `lua5.1 tests/mock.lua .`
4. Commit, then tag and push:

   ```
   git tag 0.3.0
   git push origin main 0.3.0
   ```

5. Watch the Release run under the repo's Actions tab (about two minutes).

Tags with `alpha` or `beta` in them (like `0.3.0-beta1`) are uploaded as alpha or beta files, which the
CurseForge app only offers to people who opted in.

## One-time setup

- Repo secrets (Settings > Secrets and variables > Actions): `CF_API_KEY`, `WAGO_API_TOKEN`, `WOWI_API_TOKEN`.
- Project IDs in `HUDFade.toc`: `## X-Curse-Project-ID`, `## X-Wago-ID`, `## X-WoWI-ID`.

## Game versions

The `## Interface:` line lists the Retail 12.x builds and `16001` for WoW Forever. The packager reads it and
tags each upload with the matching game versions, so one zip covers both clients. Add the new number there
when a patch changes the interface version.
