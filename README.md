# homebrew-blackmagic

A Homebrew tap for Blackmagic Design software, installing directly from Blackmagic's official
download endpoints instead of their web download form.

> **Status: both paths work.** `blackmagic-ethernet-switch` (anonymous, zero setup) and
> `blackmagic-davinci-resolve` (registration, needs the config file below) have each been installed
> and uninstalled end to end. The other casks have no recorded install yet; CI installs any anonymous cask a
> pull request changes. Remaining work is tracked in the issues.

## Why this can't be a normal cask

Blackmagic serve their installers from CloudFront using **signed URLs with a ~1 hour TTL**. The
unsigned path returns 404. There is no stable, fetchable URL to put in a cask — the real URL has to
be requested at install time from Blackmagic's download endpoint, which returns a freshly signed one.

Each cask therefore names the release it wants — `Blackmagic Ethernet Switch 1.2` — rather than an
opaque download id, and the id is looked up in Blackmagic's release catalog at fetch time. That keeps
the version the single thing a bump has to change.

This requires a **custom Homebrew download strategy**, which has two consequences you should
understand before tapping this:

1. **This tap can never be upstreamed to homebrew-cask.** Homebrew forbid custom download
   strategies in their official taps ([discussion #574](https://github.com/orgs/Homebrew/discussions/574)).
   It will only ever live as a third-party tap.
2. **Installing from this tap runs tap-provided Ruby with network access.** Homebrew does not audit
   third-party taps. The strategy code lives in `lib/` and performs an HTTP POST, then downloads
   whatever URL comes back. Read it before you trust it — that goes for any third-party tap, but it
   matters more here than for a tap that only fetches a fixed URL.

One quirk worth stating plainly: Blackmagic's download endpoint rejects any request whose
`User-Agent` contains the word `curl`, which is what Homebrew sends by default, so this tap sends no
`User-Agent` at all. Nothing else about the request differs from what their own web form sends.

Every download is checksum-verified against a `sha256` pinned in the cask, so a compromised or
re-spun artifact fails loudly rather than installing.

Blackmagic's endpoints, request shapes and the reasoning behind every design decision are recorded
in [`HANDOFF.md`](HANDOFF.md), which is the source of truth for that detail — this README repeats
only what a user needs.

## Install

This tap is private, so `brew tap` needs your GitHub credentials (SSH key or a credential helper
configured for HTTPS).

Recent Homebrew versions refuse to load formulae, casks or commands from non-official taps until you
explicitly trust them, so this is a two-step install:

```sh
brew tap mateusz-plociennik/blackmagic
brew trust --tap mateusz-plociennik/blackmagic
brew install --cask mateusz-plociennik/blackmagic/blackmagic-ethernet-switch
```

Without the `brew trust`, Homebrew reports the tap as `Untrusted` and skips its casks. Trusted
entries are recorded in `~/.homebrew/trust.json` (or under `$XDG_CONFIG_HOME/homebrew/` if that is
set). Given that this tap ships a custom download strategy — arbitrary Ruby that runs on every
install — that gate is doing exactly what it should; read `lib/` before you clear it.

Casks are prefixed `blackmagic-*`,
which keeps them collision-free against homebrew-cask (where a token clash would silently win) and
makes the whole tap discoverable via `blackmagic-<TAB>`.

## Configuration

Most Blackmagic downloads need no configuration at all — roughly two thirds of their catalog is
flagged as not requiring registration, and those resolve anonymously. **Install those with zero
setup.**

The rest — including the free edition of DaVinci Resolve — require Blackmagic's registration
details, and will refuse to install without them. Supply them in
`~/.config/bmd-tap/config.json`:

```json
{
  "country": "au",
  "firstname": "…",
  "lastname": "…",
  "email": "…",
  "phone": "…",
  "company": "…",
  "street": "…",
  "city": "…",
  "state": "…"
}
```

Every field can be overridden by an environment variable (e.g. `BMD_TAP_EMAIL`), so this works in
CI without a config file. The environment wins over the file; an empty variable counts as unset.
`$XDG_CONFIG_HOME` is honoured if you set it.

`country` defaults to `au`; it is the only field the anonymous path uses.

If a registration-path cask is missing any field, the install stops before downloading anything and
prints the path to write and the JSON to put in it. Nothing is ever prompted for mid-install, and no
field is ever guessed.

**Use your real details.** When a download requires registration, this tap is submitting *your*
registration to Blackmagic — you are the party registering, the tap is just your HTTP client. It
ships no defaults and fabricates nothing.

### Releases behind a licence agreement

Some releases require accepting a licence agreement to download. For those, and only those, the tap
refuses to install until you have written one more key:

```json
{ "agreeToTerms": true }
```

Run the install first: it stops without downloading anything and prints the agreement — the same
document Blackmagic's own download form shows you, fetched from their site, not a link to it. Read it,
and add the key if you agree.

Unlike every other setting, this one is read from the config file only — there is no
`BMD_TAP_AGREETOTERMS`. Resolving one of these downloads means the tap tells Blackmagic that you
accepted their licence, so that has to be something you did deliberately in a file you wrote, not a
variable that rode along on one command. Nothing is inferred from the fact that you ran `brew
install`, and no cask currently in the tap needs this key.

## Staying up to date

Every cask carries a `livecheck` block, so Blackmagic's own release list answers the question
"is there a newer version?":

```sh
brew livecheck --cask --newer-only mateusz-plociennik/blackmagic/blackmagic-ethernet-switch
brew outdated --cask     # once the cask has been bumped to the new version
brew upgrade --cask
```

`brew livecheck` reads upstream directly, so it sees a new Blackmagic release the moment it ships.
`brew outdated` compares your installed version against the version pinned in the cask, so it only
flags an update after the cask here has been bumped — each release needs a new `sha256` anyway.

Livecheck reads Blackmagic's release catalog — the same endpoint their own support page fetches to
render its "Latest Downloads" list, and the same one installs read to turn a release name into a
download id. No HTML is parsed. Their version-pointer endpoint would be lighter but is keyed on a
*product family* slug: Blackmagic Ethernet Switch shares the `videohub` slug with Blackmagic
Videohub, so it reports the wrong product's version. `lib/bmd_catalog.rb` has the detail.

Bumping the cask is automated: a daily GitHub Actions workflow runs `brew bump`, which compares each
cask's livecheck result against its pinned version and opens a pull request for anything newer —
downloading the artifact to compute the new `sha256`. Run it on demand from the Actions tab; tick
**report-only** to see what it would do without opening pull requests.

## Contributing

Design decisions and the researched API details are in [`HANDOFF.md`](HANDOFF.md). Work is tracked
in the repo's issues, each with its blocking dependencies listed.

## Disclaimer

Unofficial and unaffiliated with Blackmagic Design. This tap automates the same requests a browser
makes against Blackmagic's public download endpoints, with the same inputs the web form asks for —
it has no circumvention of registration, licensing, or payment built into it. Blackmagic's software
remains subject to their own licence terms.
