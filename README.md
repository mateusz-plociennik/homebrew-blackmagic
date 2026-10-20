# homebrew-blackmagic

This Homebrew tap installs Blackmagic Design software. It downloads the installers from the
official Blackmagic download endpoints. You do not use the Blackmagic web download form.

All casks have the prefix `blackmagic-`. Thus, the tokens do not collide with homebrew-cask, and
you can type `blackmagic-` and press TAB to see all casks.

## Install

1. Add the tap:

   ```sh
   brew tap mateusz-plociennik/blackmagic
   ```

2. Trust the tap. Homebrew does not load casks from a third-party tap until you trust it:

   ```sh
   brew trust --tap mateusz-plociennik/blackmagic
   ```

3. Install a cask:

   ```sh
   brew install --cask mateusz-plociennik/blackmagic/blackmagic-ethernet-switch
   ```

## Uninstall

```sh
brew uninstall --cask blackmagic-audio-monitor
```

Some casks install a full vendor bundle:

- `blackmagic-camera` also installs the Blackmagic RAW tools and plug-ins.
- `blackmagic-cintel` also installs Desktop Video drivers, Media Express and Disk Speed Test.
- `blackmagic-davinci-resolve` and `blackmagic-davinci-resolve-studio` also install control panel
  support, the Fairlight Audio Accelerator driver and the Blackmagic RAW Player.
- `blackmagic-smartview` removes only its application and application-support directories and its
  three exact package receipts. It does not run the vendor uninstaller, which forgets a broad,
  case-insensitive SmartView receipt prefix.

Where a cask invokes a vendor uninstaller, it removes the same items as that script. Vendor
uninstallers can remove shared components that other Blackmagic products use. If this occurs, install
the affected products again. Items that the vendor uninstaller keeps, for example the Blackmagic RAW
Player, stay installed and keep their package receipts. The cask files contain notes that tell you
how to change this policy.

## Registration details

Most Blackmagic downloads are anonymous. You can install them with no configuration. DaVinci Resolve
Studio is an anonymous download, but you must have a licence to activate it.
The SmartView installer includes a separate Blackmagic Design License Agreement; review its terms and
satisfy any applicable licensing, fee, or activation requirements. An anonymous download does not
waive those requirements.

Some downloads, for example the free edition of DaVinci Resolve, are available only after
registration. For these downloads, write your registration details in
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

- Use your real details. The tap sends your registration to Blackmagic. The tap does not supply
  default values.
- You can set each field with an environment variable, for example `BMD_TAP_EMAIL`. An environment
  variable overrides the file. An empty variable has no effect.
- If you set `$XDG_CONFIG_HOME`, the tap reads the file from `$XDG_CONFIG_HOME/bmd-tap/`.
- The default `country` is `au`. Anonymous downloads use only this field.

If a field is missing, the install stops before the download starts. The error message shows the
file path and the necessary JSON. The tap does not prompt you during the install.

## Licence agreements

Some releases are available only after you accept a licence agreement. For these releases, do
these steps:

1. Run `brew install`. The install stops before the download starts and shows the agreement.
2. Read the agreement.
3. If you agree, add this key to `~/.config/bmd-tap/config.json`:

   ```json
   { "agreeToTerms": true }
   ```

4. Run `brew install` again.

The tap reads this key only from the config file. No environment variable sets it. The tap tells
Blackmagic that you accept the licence, so you must accept it deliberately. At this time, no cask
in this tap uses a licence agreement.

## Updates

Each cask has a `livecheck` block that reads the Blackmagic release catalog:

```sh
brew livecheck --cask --newer-only mateusz-plociennik/blackmagic/blackmagic-ethernet-switch
brew outdated --cask
brew upgrade --cask
```

- `brew livecheck` shows a new Blackmagic release immediately.
- `brew outdated` and `brew upgrade` show a new release only after this tap updates the cask.
  A workflow does these updates two times each week.

## Security

The Blackmagic installer URLs are signed and expire after approximately one hour. Thus, a cask
cannot contain a permanent URL. A custom Homebrew download strategy gets a new signed URL at each
install. This has two results:

- **This tap cannot move to homebrew-cask.** Homebrew does not accept custom download strategies
  in official taps ([discussion #574](https://github.com/orgs/Homebrew/discussions/574)).
- **Each install runs Ruby code from this tap, with network access.** Homebrew does not audit
  third-party taps. The code is in [`lib/`](lib). Read it before you trust the tap.

The tap sends an empty `User-Agent` header. The Blackmagic endpoint rejects each `User-Agent` that
contains `curl`, which is the Homebrew default. All other request data is the same as the data
that the Blackmagic web form sends.

Each cask contains a `sha256` checksum. If a download does not agree with the checksum, the
install stops.

## Contributing

Refer to [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Disclaimer

This tap is unofficial. It has no relation to Blackmagic Design. The tap sends the same requests
and the same data as a browser that uses the Blackmagic download form. It does not bypass
registration, licences or payment. The Blackmagic licence terms apply to all Blackmagic software.
