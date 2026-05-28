# Releasing TextMate Lives

This document describes how releases of the `textmatelives/textmate` fork are
cut today. It reflects `.github/workflows/release.yml` and the version capture
in `Applications/TextMate/default.rave`.

## TL;DR

A release is cut by **landing a new top entry in `CHANGELOG.md` on `main`**.
There is no separate "tag" or "publish" step to run by hand — pushing a
`CHANGELOG.md` change to `main` triggers the `Release` workflow, which builds,
signs, notarizes, tags, and publishes the GitHub Release automatically.

## The version is defined in `CHANGELOG.md`

The first `## DATE (vX.Y.Z-undead)` heading at the top of `CHANGELOG.md` is the
single source of truth for the version. It is read in two independent places
with the same `grep`/`sed`:

- The build, to stamp the app's `CFBundleShortVersionString`:
  `Applications/TextMate/default.rave:8` captures `TEXTMATE_VERSION`, then
  `:20` passes it as `APP_VERSION` into `Info.plist` (`Info.plist:8` is
  `<string>${APP_VERSION}</string>`).
- The release workflow, for the git tag, the release title, and the release
  notes (`release.yml:32-43`).

Because both read the same heading, the shipped app reports exactly the version
in the tag — important so the updater does not offer a release to itself.

Heading format (matched by `^## .* (v.*)$`):

```
## 2026-05-28 (v2.1.1-undead)
```

The `-undead` suffix is **required** (see the guard below).

## How to cut a release

1. Add a new entry to the **top** of `CHANGELOG.md`, above the previous one:
   `## YYYY-MM-DD (vX.Y.Z-undead)`, followed by `### Section` headings and
   `*` bullets. Reference PRs/issues and commit SHAs (see existing entries).
2. Open a PR from a branch. CI (`ci.yml`) builds and tests; it does **not**
   publish.
3. Verify the notes render as intended:
   `bin/extract_changes -v X.Y.Z-undead -o - CHANGELOG.md`.
4. Merge the PR to `main`. The push to `main` touching `CHANGELOG.md` triggers
   the `Release` workflow (`release.yml:4-7`).
5. Watch the `Release` run. On success it produces the `vX.Y.Z-undead` tag and a
   public GitHub Release with the `TextMate-X.Y.Z-undead.tbz` asset attached.
6. Confirm an installed older build is offered the update (see "How users get
   it" below).

A run can also be started by hand via **workflow_dispatch** (`release.yml:8`),
but it still reads the version from the current `CHANGELOG.md` top entry.

## What the workflow does (`release.yml`)

Runs on `macos-26`, 60-minute timeout, `contents: write`.

1. **Extract version** from `CHANGELOG.md` (`:32-43`).
2. **Guard — must be `-undead`** (`:45-59`). If the top version does not contain
   `-undead`, the run skips (no release).
3. **Skip if the tag already exists** on `origin` (`:61-74`). Re-running for an
   already-released version is a no-op.
4. **Install deps** via Homebrew (`:76-78`).
5. **Import the Developer ID certificate** from secrets into an ephemeral
   keychain and resolve the signing identity (`:80-109`).
6. **Pre-seed `local.rave`** with the Homebrew prefix, the signing identity, and
   hardened-runtime codesign flags, then `./configure` and `ninja TextMate`
   (`:111-127`). (This pre-seed is intentional and distinct from the local
   developer flow, where `configure` derives the prefix itself.)
7. **Sign inside-out**: re-sign every embedded Mach-O, re-seal nested bundles,
   then re-sign the outer `.app` with release entitlements
   (`CS_GET_TASK_ALLOW=false`) (`:143-194`), and verify codesign + hardened
   runtime (`:196-202`).
8. **Notarize** via `notarytool submit --wait`, parsing the JSON status
   (`--wait` can exit 0 on `Invalid`, so the status is checked explicitly)
   (`:204-233`).
9. **Staple** the ticket (retried until CloudKit propagates) and **verify
   Gatekeeper** with `spctl --assess` (`:235-255`).
10. **Build the `.tbz`** `TextMate-${VERSION}.tbz` (`:257-268`).
11. **Extract release notes** with `bin/extract_changes` (`:270-282`).
12. **Create the GitHub Release** with `gh release create "v${VERSION}"` — no
    `--prerelease`/`--draft`, so it becomes `releases/latest` (`:284-295`).
13. **Delete the ephemeral keychain** (always) (`:297-299`).

## Required GitHub secrets

`release.yml` consumes (the build will fail at signing/notarization without
them):

- `MAC_CERTIFICATE_P12` — base64-encoded Developer ID Application `.p12`.
- `MAC_CERTIFICATE_PWD` — password for that `.p12`.
- `APPLE_ID`, `APPLE_ID_PWD`, `APPLE_TEAM_ID` — notarization credentials
  (`APPLE_ID_PWD` is an app-specific password).

The keychain password is ephemeral (`KEYCHAIN_PWD` = run id), and the certificate
identity is matched by name (`CERT_IDENTITY_NAME` = "Developer ID Application").

## How users get the update

The app checks `api.github.com/repos/textmatelives/textmate/releases/latest`
(`Applications/TextMate/src/AppController.mm:494`), compares the running
`CFBundleShortVersionString` against the release `tag_name`, downloads the first
`.tbz` asset, and installs it only if the downloaded bundle carries a valid
Developer ID Application signature whose Team Identifier matches the **running**
app (`Frameworks/SoftwareUpdate/src/SoftwareUpdate.mm`). It then swaps the bundle
in place and relaunches. A build signed by a different team — or unsigned — is
refused.

## Gotchas

- **Merging a `CHANGELOG.md` change to `main` is the publish action.** There is
  no dry run on `main`; treat the merge as the release.
- **The top entry wins.** Only the first `## ... (vX.Y.Z)` heading is read, so
  the new entry must be above the previous one.
- **`-undead` is mandatory**; a version without it silently skips the release.
- **Tags are immutable here.** To re-release, bump to a new version; the workflow
  will not overwrite an existing tag.
- **A release built without the Developer ID** cannot be consumed by the updater
  (the trust gate requires the same team), so releases must come from the
  signed CI path, not an ad-hoc local build.
