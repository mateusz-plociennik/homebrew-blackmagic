# Handoff — Blackmagic Design Homebrew tap

Status: **research complete, design agreed, nothing built yet.** Repo has zero commits.

Next session: implement the POC (download strategy + one cask + README + CI), then run a full
install/uninstall cycle.

## Goal

A third-party Homebrew tap that installs Blackmagic Design software directly, without going
through blackmagicdesign.com's web download form.

## The download mechanism (researched and verified live)

BMD's download page is an AngularJS app (`https://jslibs.blackmagicdesign.com/bundles/js/support-bundle.js`).
Three relevant endpoints:

### 1. Catalog
`GET https://www.blackmagicdesign.com/api/support/{country}/downloads.json` — ~1.5 MB (gzipped to
~226 KB, `cache-control: max-age=900`), 1219 releases.
Entry shape:

```json
{ "id": "<releaseId>", "name": "Blackmagic Ethernet Switch 1.2",
  "urls": { "Mac OS X": [{ "downloadId": "8d83aa9a…", "product": "videohub",
                           "major": 1, "minor": 2, "releaseNum": 0, "buildNum": 0 }] },
  "requiresRegistration": false, "requiresTermsAndConditions": false }
```

Flag distribution: **836** need nothing · **160** registration · **223** registration + T&C.
The website fetches this once per page load and filters client-side (memoised in `getSupportDownloadsModel`).
The support pages are entirely client-rendered — `window.__bmd` carries only nav, privacy,
translations and locale — so the "Latest Downloads" list is built from this catalog and nothing
lighter exists to read.

**Release names discriminate products, and the suffix matters.** `DaVinci Resolve 21.0.4 Update` and
`DaVinci Resolve Studio 21.0.4 Update` are different products; pre-16 Studio releases were named
`DaVinci Resolve 15.3 Studio`, so a prefix match on `DaVinci Resolve ` would swallow them. Observed
suffixes across the catalog: `Update` (570), none (417), `SDK` (179), `Studio` (30),
`Studio Update` (9), and 10 `Beta`/`Public Beta` releases. Match the whole name, never a prefix.

**Two distinct ID namespaces:** `releaseId` is the GUID in the web page path
(`/support/download/65960dbc…/Mac OS X`), one per release across all platforms. `downloadId` is
per *(release × platform)* and is what the resolve endpoint takes. Posting a releaseId returns
`400 The download id '…' was not found`. Historic versions retain fixed downloadIds, so they look
permanent.

### 2. Version pointer
`GET https://www.blackmagicdesign.com/api/support/latest-stable-version/{product}/{platform}`
→ `{"mac":{"releaseId":…,"downloadId":…,"major":21,"minor":0,"releaseNum":4}}`. Omit the platform to
get every platform key at once (`mac`, `wintel`, `winx86`, `winarm`, `linux`).
`POST /api/support/latest-version {product, platform}` is the same shape including betas.

**Unusable for livecheck on most casks.** The `{product}` segment is the catalog's `product` field,
which is a product *family*, not a product: Blackmagic Ethernet Switch's slug is `videohub`, and the
pointer answers with Blackmagic Videohub 11.0.1. Nothing distinguishes them, and an unknown slug is
indistinguishable from a known one — `ethernetswitch`, `ethernet-switch` and `totalnonsensexyz` all
return `{"mac":null}` with a 200. `davinci-resolve` does resolve correctly (21.0.4).

**Neither endpoint can list releases** — both return exactly one release per platform. The catalog is
the only enumeration. `nav.json` (82 KB, `/api/support/{country}/nav.json`) maps products to families
but carries no versions, `/api/v1/model/` is a countries list, and `sw.blackmagicdesign.com` has no
directory listing. So livecheck reads the catalog; see `lib/bmd_livecheck.rb`.

### 3. Link resolution
`POST https://www.blackmagicdesign.com/api/register/{country}/download/{downloadId}`,
`content-type: application/json`, plus `origin`/`referer` headers for `www.blackmagicdesign.com`.
Response body is **plain text: a CloudFront-signed URL**, TTL ~1h:

```
https://sw.blackmagicdesign.com/EthernetSwitch/v1.2/Blackmagic_Ethernet_Switch_Macintosh_1.2.zip?Key-Pair-Id=…&Signature=…&Expires=…
```

The unsigned path **404s** — signing is mandatory, so the URL cannot be hardcoded in a cask.
This is why a custom download strategy is required (cf.
https://github.com/orgs/Homebrew/discussions/574).

**Body shapes** — discriminated by the catalog's `requiresRegistration`:

| `requiresRegistration` | Required fields |
|---|---|
| `false` (the "Download only" button on the site) | `platform`, `policy: true`, `country`, `downloadOnly: true`, `origin` |
| `true` | above + `firstname`, `lastname`, `email`, `phone`, `company`, `street`, `city`, `state`, `hasAgreedToTerms` |

Both verified working. `product` is **optional** (tested). `country` is **required** (omitting → 400).
Anonymous body against a registration-required item → `403 Must register to be able to perform the download`.

**Throttle:** back-to-back POSTs return a bare `400 Bad Request`; ~30s spacing always worked.
Irrelevant for one-resolve-per-install, but the phase-3 scraper must pace itself or it will read
spurious 400s as failures.

**Artifact identity is stable across resolves.** Two resolves of the same downloadId returned
different signatures pointing at the same S3 object (identical `content-length: 368867738`, stable
`etag: "46adb07912f0f2b5cb23f0b22628b843-44"`). So a pinned `sha256` is valid for the life of a version.

**No BMD session/profile endpoint exists** in their JS. Fields that appear prefilled on the website
are Chrome autofill; "Australia" comes from the `/au/` path segment via `getCountry()`, not browser
language. A tap must therefore supply `country` explicitly.

## Agreed design

**Tap:** `mateusz-plociennik/blackmagic` — repo `github.com/mateusz-plociennik/homebrew-blackmagic`,
default branch `main`.

```
brew install --cask mateusz-plociennik/blackmagic/blackmagic-ethernet-switch
```

**Custom download strategy** in `lib/bmd_download_strategy.rb`, a `CurlDownloadStrategy` subclass
shared by all casks via `require_relative`. Overrides `_fetch` to POST for a signed URL, then curl that.

**Cask `url` holds the stable *unsigned* path** with `#{version}` interpolated, never the signed one.
Reason: `AbstractFileDownloadStrategy#cached_location`
(`$(brew --repo)/Library/Homebrew/download_strategy/abstract_file_download_strategy.rb:33`) keys the
cache on `Digest::SHA256.hexdigest(url)`. A signed URL differs every resolve → a new 370 MB cache
entry per install, and `brew fetch` followed by `brew install` would re-download. The unsigned path
is stable, encodes the version, and keeps the cask auditable. It is never actually fetched.

**`bmd_download_id` hardcoded per cask** (not looked up at install time). Both drift modes are loud:
a retired ID fails at resolve time with BMD's own message; a respun artifact fails on checksum.
Catalog lookup belongs in the scraper, not the installer.

**Real pinned `sha256`**, never `:no_check`.

**Config** at `~/.config/bmd-tap/config.json` (XDG), env-var overridable
(`BMD_TAP_COUNTRY`, `BMD_TAP_EMAIL`, …):

```json
{ "country": "au", "firstname": "…", "lastname": "…", "email": "…",
  "phone": "…", "company": "…", "street": "…", "city": "…", "state": "…" }
```

`country` defaults to `au`, so **anonymous casks install with zero setup**. Only registration-path
casks require the file. Real details only — the tap must never ship or fabricate identity values;
the user is the party registering, the tap is just their HTTP client.

**On failure: no retry.** Print BMD's response body plus a one-line explanation, exit non-zero.
Never prompt interactively from inside a download strategy (breaks `--quiet`, CI, parallel installs).

**Cask tokens prefixed `blackmagic-*`.** Verified in `cask/cask_loader.rb:592-626`: homebrew/cask
silently wins any token collision, and 2+ third-party matches raise `TapCaskAmbiguityError`. The
prefix keeps unqualified `brew install --cask blackmagic-…` reliable and makes the tap tab-completable.
Upstreaming is impossible anyway — homebrew/cask forbids custom download strategies — so the
prefix costs nothing.

## POC target: `blackmagic-ethernet-switch`

Chosen because it takes the anonymous path (no PII) and the artifact is already inspected.

- `downloadId` (Mac): `8d83aa9aa2684f1788d1b68da1c01ae7`
- version `1.2`, unsigned url `https://sw.blackmagicdesign.com/EthernetSwitch/v#{version}/Blackmagic_Ethernet_Switch_Macintosh_#{version}.zip`
- `sha256 a34c37122939e82b60e08afd0d442fbc5d48bf034d107c36eec6663e3c3069fb`
- structure: `.zip` → `Blackmagic_Ethernet_Switch_1.2.dmg` → `Install Ethernet Switch 1.2.pkg` (807 MB).
  Homebrew's `extract_nestedly` unwraps zip→dmg automatically, so a `pkg` stanza works directly.
- pkg receipts: `com.blackmagic-design.EthernetSwitch`, `…EthernetSwitchAssets`, `…EthernetSwitchUninstaller`
  → `uninstall pkgutil: "com.blackmagic-design.EthernetSwitch*"`

A copy of the zip may still be at `/tmp/es.zip` (369 MB) — check before re-downloading.

## Work remaining this session

1. `git branch -m master main`; rename GitHub repo `homebrew-tap` → `homebrew-blackmagic`
   (`gh repo rename homebrew-blackmagic`) and the local directory to match.
2. `lib/bmd_download_strategy.rb`
3. `Casks/blackmagic-ethernet-switch.rb`
4. `README.md` — install line, config format, and an explicit note that the custom download
   strategy makes this permanently non-upstreamable to homebrew-cask (users run tap-provided Ruby
   with network access on every install).
5. `.github/workflows/ci.yml` — `brew test-bot --only-tap-syntax`
6. **User approved a full real install** (`brew install --cask`, sudo prompt, 807 MB pkg) followed by
   `brew uninstall --cask` to prove the `uninstall pkgutil:` stanza.

### Then: DaVinci Resolve (exercises the registration path)

Free Resolve is `requiresRegistration: true`; Resolve **Studio** is `false` (inverted from what you'd
expect). Latest at time of research: 21.0.4, Mac downloadIds `b8e8e421548d4475a36a91155f81f3f2`
(free) / `3598b54de60948399b034409ab19fa9a` (Studio). Consider `conflicts_with` between the two.
Multi-GB downloads — slow to iterate on.

### Deferred (phase 3, explicitly out of scope)

- Catalog scraper emitting `brew bump-cask-pr` (which rewrites `version` + `sha256` and opens a PR)
  rather than hand-editing cask files. Must pace requests ≥30s.
- The 223 `requiresTermsAndConditions` products. A cask that programmatically accepts a licence on
  the user's behalf must display the terms (present in the catalog JSON as `termsAndConditions`) and
  require an explicit opt-in in the config. Do not design this until a T&C product is actually in scope.

## Notes for the next agent

- The user is a Blackmagic Design employee; their motivation is skipping the website for official
  releases. Their real registration details were supplied in-session for testing the registration
  path and are **deliberately not recorded here** — ask for them if you need to test that path, and
  do not commit them.
- The user's global style preference is extreme concision.
- `WebFetch` returned "No response from model" for both blackmagicdesign.com and the GitHub
  discussion. All research above was done with `curl` + `python3` instead. Use curl.

## Suggested skills

- `mattpocock-skills:code-review` — after the strategy and cask are written, before the real install.
  The strategy handles user PII and executes a fetch against a URL returned by a remote endpoint;
  worth a careful pass.
- `security-review` — same rationale, specifically for the config-file handling and the
  trust boundary around the resolved URL.
- Do **not** re-run `mattpocock-skills:grilling` — the design tree is closed; every decision above
  was explicitly confirmed by the user.
