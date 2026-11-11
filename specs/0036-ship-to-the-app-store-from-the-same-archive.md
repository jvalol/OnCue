---
title: Ship to the App Store from the same archive
status: shipped
created: 2026-09-22
commits: bc78b74 (approval), 21ba5dd (implementation), cda78ac (team switch), 49c5f42 (dry run), 2040271 (released in 4.8)
---

## Problem
`scripts/release` produces exactly one artifact: a Developer ID build, notarized, stapled, zipped
into `site/downloads`, with the Homebrew cask rewritten to point at it. The App Store record needs
a different one. It is signed with a distribution certificate rather than Developer ID, carries an
embedded provisioning profile, exports as `app-store-connect` rather than `developer-id`, and is
uploaded to App Store Connect rather than copied into a folder. None of that exists, so there is no
way to ship to the record at all.

The record has been on 3.0.3 since 2021 and is where almost all of OnCue's traffic comes from.
Reverting the bundle ID (`a687db6`) removed the repo-side blocker; this removes the tooling one.
Everything else standing between 4.x and the store is account work or listing work, not code.

## Non-goals
- The App Transfer itself, the new certificates, and the notarytool profile. Those need an account
  that does not exist yet, and they are recorded in `.claude/memory/app-store-transfer-plan.md`.
- Listing copy, screenshots and the privacy label. Separate work, none of it in this repo.
- Replacing the Developer ID path. Both channels continue, and only the Developer ID artifact ever
  touches `site/downloads` or the cask.
- Anything on the App Store Connect side past the upload. No metadata, no submission, no release.
- Shipping to the store from team A2MVZ4JVLC, which this spec makes impossible rather than merely
  discouraged.

## Behaviour (acceptance criteria)
- [x] One `xcodebuild archive`, exported twice. Both artifacts report the same `CFBundleVersion`.
- [x] With the store mode unset, a release is what it is today: the same zip in `site/downloads`,
      the same cask rewrite, `scripts/check-tap` unaffected.
- [x] The store path refuses to run while `TEAM` is `A2MVZ4JVLC`, before anything is built.
- [x] The store export produces a signed `.pkg` carrying an embedded provisioning profile.
- [x] The upload authenticates with an App Store Connect API key read from the environment. No
      credential, key or password is written into the repo.
- [x] A failure on the store side leaves `site/downloads` and the cask exactly as a successful
      Developer ID release would. The direct channel is never half-shipped because the store was.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**One archive, two exports.** This is the decision the spec exists to make. The script already goes
to real lengths over `CFBundleVersion`: it reads the number back off the built app rather than the
source file, refuses to continue unless it is greater than every number already shipped, and writes
it back so the repo records the build that exists. Two separate archives would hand one marketing
version two different build numbers and break that invariant silently. Exporting the same archive
twice also makes it provable that both channels carry identical code.

**The export options.** `method: app-store-connect`. The older `app-store` is deprecated in
Xcode 27 and `xcodebuild -help` says to use the new name. `destination` takes `export` or `upload`,
which is the same key the existing plist already sets to `export`, so a local `.pkg` to inspect and
a direct upload are the same mechanism with one value changed.

**Authentication and upload.** `xcodebuild -exportArchive` with `destination: upload`, and
`-authenticationKeyPath`, `-authenticationKeyID` and `-authenticationKeyIssuerID` with the key path
coming from the environment. It is the same call and the same plist as the export with one value
changed. `xcrun altool --upload-app` is still on disk in Xcode 27 but Apple deprecated it for
uploads and points at Transporter and `xcodebuild`, so it is not a fallback here. If the
`xcodebuild` upload fails, the fallback is the Transporter app by hand with the exported `.pkg`, not
a second script path.

**Every version goes to the store.** The store trails the direct channel by review time whatever is
decided, so the only real choice is whether every version is submitted, and it is. Store users are
the ones on 3.0.3 with the silent-failure reviews; a patch release that goes direct only leaves them
on the bug. Submission is part of releasing, so the store mode is set on every release run rather
than remembered later. Skipping the store for a version is a decision made per release with the
variable off. For the days a version sits in review, the direct channel and the store disagree
about "current"; nothing checks against that. `scripts/check-tap` stays direct-only, and the store
has its own dashboard.

**The site names its download.** A Mac App Store export embeds a provisioning profile, and Xcode
adds `com.apple.application-identifier` and `com.apple.developer.team-identifier` to the signed
entitlements. The Developer ID export does not, which is why the front page shows exactly the five
authored keys. Neither added key is a permission; the claim the page makes, no
`com.apple.security.network.*`, is true of both builds. The listing stays as it is, the block says
it describes the copy downloaded from that page, and one sentence says the App Store copy shows two
extra keys naming the app and the team, still no network. Showing what to look for instead of the
exact list was rejected as weaker evidence. The copy is Jake's.

**The dry run waits for the new account.** Exporting with `method: app-store-connect` needs a Mac
App Distribution certificate, and this Mac has none: Developer ID for EggDevil and two development
certificates. Creating one would mean more setup on the EggDevil team, which the non-goals already
rule out. So the first export on the new team is the dry run, with `destination: export` and the
`.pkg` inspected before anything is uploaded. Until then the store path is written, refuses at
preflight on this team, and is otherwise unexercised.

**Notarization does not apply to the store artifact.** Apple notarizes App Store builds on their
side. The existing notarize, staple and Gatekeeper block stays where it is and continues to guard
only the Developer ID zip, which is the one a user downloads and double-clicks.

**Ordering.** The store export runs last, after the zip has landed in `site/downloads` and the cask
has been rewritten. A store failure then costs an upload, not a half-finished direct release.

**Mode selection.** An environment variable, matching `ALLOW_DIRTY` and `SKIP_TAP`. Default off, so
an ordinary release is unchanged.

**The refusal.** "Never ship to the store from EggDevil" currently lives in a memory file, which
protects it exactly as long as someone reads that file. In the script it is enforced, and the one
release where it matters is the one where somebody is moving fast.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] With the store mode set and `TEAM` still `A2MVZ4JVLC`, the script fails at preflight and
      nothing is built
- [x] Deferred to the new account: a `destination: export` run there produces a signed `.pkg` with
      an embedded provisioning profile, and its entitlements are the five authored keys plus the
      two identifier keys
- [x] With the store mode unset, the Developer ID path, the cask and `scripts/check-tap` behave
      exactly as they do today

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

This change has no user-facing copy. Everything it adds is script output read by Jake, which
follows the existing `release:` prefix and says what failed and what to do about it.

## Tasks
- [x] The second ExportOptions plist and the second export
- [x] The `A2MVZ4JVLC` refusal, in the preflight
- [x] Authentication wired from the environment
- [x] The site's entitlement block names the download it describes and says what the store copy
      shows instead (marked copy for Jake)
- [x] Deferred to the new account: the first `destination: export` run, and the `.pkg` inspected

## Verification
- `scripts/release` gained `APP_STORE=export|upload`, a store preflight, and a store section that
  runs after the direct summary prints. The direct path is untouched: no line before the store
  section changed except the "releasing" line, which now says whether the store is in play.
- The preflight was run in isolation on this Mac (the case block lifted into a scratch script,
  since running `scripts/release` itself builds a release): `APP_STORE` unset passes; `upload` and
  `export` both refuse with `TEAM=A2MVZ4JVLC` before anything else is checked; a wrong value is
  refused; with `TEAM` set to another team and no distribution certificate in the keychain, it
  refuses on the certificate. `sh -n` accepts the whole script.
- The store export itself, the `.pkg` checks (signature, embedded profile, `CFBundleVersion` equal
  to the zip's, no network entitlement) and the upload have not run. They cannot until the new
  team exists with a Mac App Store distribution certificate and a Mac Installer Distribution
  certificate. The certificate names the preflight greps for (`Apple Distribution` or
  `3rd Party Mac Developer Application`, `3rd Party Mac Developer Installer` or
  `Mac Installer Distribution`) and the `pkgutil --expand-full` layout are from documentation,
  not from a run. The first `APP_STORE=export` on the new team is where those get confirmed; the
  gate above stays open until then.
- `manageAppVersionAndBuildNumber` is set false in the store plist so Xcode cannot rewrite the
  build number on upload.
- **Dry run on the new team (2026-09-22, team `DC3U4XZMM4`, after the transfer completed):** one
  archive, exported with `method: app-store-connect`, `destination: export`, run by hand with the
  same plist and checks the script uses. Everything the script assumes held. `OnCue.pkg` signed by
  `3rd Party Mac Developer Installer: JACOB VANALSTYNE (DC3U4XZMM4)`; the app inside signed by
  `Apple Distribution: JACOB VANALSTYNE (DC3U4XZMM4)` with the hardened runtime;
  `embedded.provisionprofile` present; `pkgutil --expand-full` puts the app at
  `com.eggdevil.oncue.pkg/Payload/OnCue.app`, within the script's `find` depth; bundle ID
  `com.eggdevil.oncue`; `CFBundleVersion` 852, the number in the source file. Entitlements are the
  five authored keys plus `com.apple.application-identifier` and `com.apple.developer.team-identifier`
  and nothing else, so the site's "two more lines" is exact. The certificate names the preflight
  greps for are confirmed: `Apple Distribution` and `3rd Party Mac Developer Installer`.
  One thing to know: `pkgutil --check-signature` labels the installer certificate "(Development)".
  That is pkgutil's word for anything that isn't Developer ID, not a sign of the wrong certificate.
- **4.8, the first real run (2026-09-22, `APP_STORE=upload scripts/release`):** preflight,
  `scripts/check`, one archive, Developer ID export, signature checks, then notarization, which
  Apple held In Progress for two hours fifty-three minutes. A second submission of the same zip as a
  probe sat the same way, so it was the new team's queue, not the submission; both were accepted
  within a minute of each other at 14:38 MDT. The script then stapled, packaged, copied the zip
  into `site/downloads` (build 856, Gatekeeper `Notarized Developer ID`), rewrote the cask, and
  ran its store section: the export and every check on the `.pkg` passed and the build number
  matched the zip's. Its upload was refused, "The entity has been replaced", because the same
  build had been uploaded by hand seconds earlier from the same archive with the same plist and
  the same `xcodebuild` upload command, while the notarization looked stuck. That upload
  succeeded, so App Store Connect holds one build 856. The ordering did what it was for: the
  direct release was complete before the store step failed, and the script said so and stopped.
  The upload mechanism is proven by the by-hand run of the identical command; the script's own
  upload line has not yet succeeded in situ, which the next release will show.
- Closed with 4.8. Tap pushed, `scripts/check-tap` green: 4.8 installable, cask and zip agree.
- The site's entitlement block got two marked sentences: the command is introduced as the copy
  downloaded from that page, and one line says what the App Store copy shows from 4.8 on.
- `scripts/ship-check` fails on those two markers, as designed, so `scripts/check` fails at its
  first step until Jake strikes them. The build and unit tests were run separately the way
  `scripts/check` runs them: clean build, 254 tests, 0 failures, 1 skipped, no warnings. Nothing
  under `OnCue/` changed, so that is the same build as `master`.

## Open questions
1. Resolved (Jake, 2026-09-22): the store build shows two more keys, both identifiers, neither a
   permission. The site keeps the exact listing, says which download it describes, and adds one
   sentence for the store copy. See "The site names its download" in Design.

   The mismatch is not new: 3.0.3 is on the store today with the Countly SDK in it, so the version
   with all the traffic already contradicts the page. 4.8 fixes the analytics half; the copy change
   fixes the other.

2. Resolved (Jake, 2026-09-22): every version is submitted, the store trails by review time, and
   nothing checks the two channels against each other. See "Every version goes to the store".

3. Resolved (Jake, 2026-09-22): `xcodebuild` with `destination: upload`. `altool` is deprecated
   for uploads and is not a fallback. Settling it also moved the dry run to the new account, since
   the current team has no distribution certificate and getting one is EggDevil setup the non-goals
   rule out. The gate and task that said "against the current team" were contradicting the refusal
   anyway.
