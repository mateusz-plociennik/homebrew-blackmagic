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

**The catalog is a full history, not a "latest" list** — 1220 entries; Ethernet Switch 1.0, 1.1 and
1.2 are all in it and Desktop Video has 168. Load-bearing since #8: a cask pinned behind the current
release still finds its downloadId, and 1.1's id still resolves to a signed URL today.

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
| `true` (their registration form) | `platform`, `policy: true`, `country`, `origin`, **`product`**, `firstname`, `lastname`, `email`, `phone`, `company`, `street`, `city`, `state` |

Both verified working. `country` is **required** (omitting → 400).

**`product` is what discriminates the two bodies** — corrected in #3; the earlier note here called it
optional, which held only for the anonymous path. Their modal is explicit about it
(`SupportModalDownloadStartCtrl`): `downloadNow()` — the "Download only" button — sets
`downloadOnly = true` and sends no `product`, while `handleFormSubmission()` fills `product` in from
the chosen related product (or the release name) and never sets `downloadOnly`. The endpoint agrees:
against a registration-gated release, a body carrying every identity field but no `product` is still
`403 Must register to be able to perform the download`, and the same body with a non-empty `product`
returns a signed URL. An empty-string `product` is a 403 too. `downloadOnly` makes no difference
either way, and no terms flag is wanted — `hasAgreedToTerms` was in the earlier table but is not
required for a `requiresTermsAndConditions: false` release, so the tap sends nothing of the kind.
The value passed is the cask's own product name (`"DaVinci Resolve"`), which the endpoint accepts.

An anonymous body against a registration-required item → `403 Must register to be able to perform the
download`.

~~**Throttle:** back-to-back POSTs return a bare `400 Bad Request`; ~30s spacing always worked.~~
**There is no throttle** (established in #2). The bare `400` is a User-Agent filter: this endpoint
rejects any request whose UA contains the substring `curl` — a match on the name alone, so
`curl-lover/1.0` is rejected too and Homebrew's own UA with the `curl/8.7.1` suffix stripped is
accepted. An empty UA works; see `BmdDownloadStrategy::USER_AGENT`. Three back-to-back POSTs all
succeeded, so nothing forces a pacing floor on the phase-3 scraper. Only this endpoint filters —
`downloads.json` on the same host and the artifact host do not.

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

~~**`bmd_download_id` hardcoded per cask** (not looked up at install time). Both drift modes are loud:
a retired ID fails at resolve time with BMD's own message; a respun artifact fails on checksum.
Catalog lookup belongs in the scraper, not the installer.~~

**Reversed in #8.** The cask names the product (`data: { "product" => "Blackmagic Ethernet Switch" }`)
and `BmdCatalog.mac_download_id` pairs it with `version` to look the id up at fetch time. (#8 had the
cask spell out the whole release name; #9 replaced that with product-plus-version, because point
releases are named `<product> <version> Update` and the suffix is not derivable from a version — a cask
holding a full release name would keep the old name after a bump. See `BmdCatalog::OPTIONAL_SUFFIX`.)
The drift argument
covered a *retired* id, not a *stale* one — and a version bump produces exactly a stale one.
`brew bump-cask-pr` rewrites only `version`, `url` and `sha256`, and `_fetch` ignores `url`, so a
pinned id would have it download the old artifact, pin that artifact's checksum under the new version
number, and install 1.2 while claiming 1.3 — the one drift mode that is silent. Cost of the lookup is
226 KB / ~2 s against a 352 MB download, and none at all on a cache hit.

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

**Requires go *inside* the `cask` block, and use `require`, not `require_relative`.** Both are forced
by `brew bump-cask-pr`, which reloads the cask from its own *contents* twice (`bump-cask-pr.rb:322`
and `:356`) to compute the new checksum:

- `FromContentLoader.try_new` accepts only content matching `/\A\s*cask ... end\s*\Z/m`
  (`cask/cask_loader.rb:80-93`), so a `require` line above the block makes the file unloadable —
  `Error: Cask <the entire file, downcased> is unavailable: No Cask with this name exists.`
- that loader `instance_eval`s the contents with `Library/Homebrew` as the base, so
  `require_relative "../lib/…"` resolves to `/opt/homebrew/Library/Homebrew/lib/…` and raises
  LoadError. `require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/…"` works under every
  loader (`require` accepts a Pathname via `#to_path`).

Neither shows up under `brew install`, `fetch`, `livecheck`, `audit`, `style` or `test-bot` — only
`bump-cask-pr` reloads from contents, so this is exactly the trap that would have surfaced in phase 3.

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

### DaVinci Resolve (exercises the registration path) — **done in #3**

Free Resolve is `requiresRegistration: true`; Resolve **Studio** is `false` (inverted from what you'd
expect). Neither is `requiresTermsAndConditions`. Multi-GB downloads (21.1 is 3.8 GB zipped, a 5.8 GB
pkg) — slow to iterate on.

`Casks/blackmagic-davinci-resolve.rb` was scaffolded by `bin/generate-cask` and install-verified at
21.1: install, uninstall, reinstall, on a machine that also had Fairlight Live. Two things that pass
came out of it, both about *shared* payload:

- **`com.blackmagic-design.Manifest*` is not Resolve-exclusive.** The pkg writes four `Manifest*`
  receipts, but only `ManifestLite` is Resolve's own (Resolve.app, Proxy Generator Lite, Remote
  Monitor); `ManifestPanels`, `ManifestBlackmagicRawPlayer` and `ManifestFairlightAudioAccelerator`
  arrive with other Blackmagic installers too, and Fairlight Live adds `ManifestFairlightLive`,
  `ManifestPanelsFairlightLive` and `ManifestProxyGenerator`. `pkgutil` uninstalls are not
  reference-counted, so the prefix regex `bin/generate-cask` derives would have deleted a co-installed
  product's files. The cask uninstalls `ManifestLite` only.
- **`/Applications/DaVinci Resolve` is a shared directory** — Fairlight Live keeps
  `Fairlight Studio Utility.app` and its panel setup app there — so no blanket `delete:`. But
  `/Applications/Blackmagic Proxy Generator Lite.app` *is* deleted outright: two receipts claim that
  bundle, `pkgutil` removed only the files `ManifestLite` lists (Info.plist and the binary among them)
  and left ~200 stale files, i.e. an app that no longer launches. Reinstalling either product restores
  it whole.

Also worth knowing: Resolve's artifact path carries a build suffix the version does not imply
(`/DaVinciResolve/v21.1-1/`), and its installer writes its OS check with the literal first
(`compareVersions('15.0', system.version.ProductVersion)`), which is why
`BmdCaskGenerator::MIN_OS_PATTERNS` has to match both argument orders.

Still open: `conflicts_with` between free Resolve and Studio, once a Studio cask exists.

### Deferred (phase 3, explicitly out of scope)

- ~~Catalog scraper emitting `brew bump-cask-pr`.~~ **Built in #5, and there is no scraper.**
  `brew bump --cask --tap … --open-pr --no-fork` already does every part of it: runs livecheck (which
  reads the catalog), diffs against the pinned version, checks GitHub for an existing bump PR, and
  calls `bump-cask-pr` to download, checksum and open. `.github/workflows/bump.yml` runs it daily.
  Since #8, `--version` is sufficient — the downloadId follows from the version.
- ~~The 223 `requiresTermsAndConditions` products.~~ **Built in #6.** `_fetch` refuses a release whose
  catalog entry sets the flag unless the config file carries `"agreeToTerms": true`.
  `BmdConfig.accepts_terms?` reads the file only — no environment variable — so acceptance cannot ride
  along on one `brew install` invocation.

  The note above (and the issue) said the terms text is in the catalog as `termsAndConditions`. It is
  not: that field is a *slug* naming a licence document (`"bmd-braw-sdk-2"`), and six slugs cover all
  224 gated macOS releases. The text comes from the modal Blackmagic's own download button opens,
  `/support/modal/download-with-terms-start/<slug>`, which their `support-bundle.js` builds and
  renders as step 2 of the download form; every `/api/…/terms…` shape 404s. `BmdTerms` fetches that
  fragment and lifts the agreement out of its `<div class="tandc">`. If it cannot, it raises — the
  install still stops, and the tap never asks anyone to agree to a document it could not show them.

  No cask in the tap exercises this yet, because the two eligible products (`Blackmagic RAW`,
  `Blackmagic Fairlight Sound Library`) are also registration-gated, and bootstrapping either means
  downloading the artifact, which means someone accepting their licence first. Verified live instead:
  `BmdCatalog.mac_release("Blackmagic RAW", "5.1")` → flag set, slug `bmd-braw-sdk-2`, refusal
  carrying all 22.6 KB of the real agreement.

### `brew audit --cask --online` (#7 — the constraint that turned out not to exist)

The comment that used to sit on `resolve_url_basename_time_file_size` claimed an online audit can
never pass here. It can, and does — verified by running it against `blackmagic-ethernet-switch`:

- `Cask::Audit#audit_url_https_availability` returns early for any `url` with a `using:` strategy, so
  the deliberately-404ing unsigned path is never probed.
- `audit_download` then fetches through `BmdDownloadStrategy#_fetch`, which mints a real signed URL.

The override is still load-bearing — for the download cache key, not for audit. Do not remove it.

The catch is `audit_download`: online audit downloads the whole artifact (~350 MB for Ethernet
Switch, multiple GB for Resolve), and registration-path casks need a config file CI does not have.
That is why per-PR CI stays on `--only-tap-syntax` and the online audit is a manual/weekly job over
the anonymous casks only. Still unproven by anything cheap: that Blackmagic's resolve endpoint is
alive. `bump.yml` exercises it daily as a side effect of checksumming; a dedicated health check that
resolves a signed URL without downloading it was considered and deferred as duplicate coverage.

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
