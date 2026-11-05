# tblisonb's F-Droid repo

An [F-Droid](https://f-droid.org) repository of [Segue](https://github.com/tblisonb/Segue) and
[MediaSync](https://github.com/tblisonb/MediaSync)'s Android app. F-Droid installs them and keeps
them up to date.

**Adding it:** on your phone, open <https://tblisonb.github.io/fdroid/> and tap the link there, or
add the address it shows in F-Droid's **Settings > Repositories**.

The APKs are the same files as the apps' GitHub releases, signed with the same key, so F-Droid
updates copies installed from GitHub, and the other way round. The repo itself is signed with a
separate key, which F-Droid checks every update against.

## How it's built

GitHub Pages serves the `gh-pages` branch: the repo F-Droid reads (`repo/`) and the page that says
how to add it. `main` holds what builds it:

- `config.yml`: [fdroidserver](https://f-droid.org/docs/Setup_an_F-Droid_App_Repo/)'s settings.
  The signing key and its passwords aren't here: they're `~/.android/fdroid-repo.p12` and
  `~/.android/fdroid-repo.properties` on the PC that publishes.
- `metadata/`: each app's listing (summary, description, links), and its "What's new" for each
  version, written from the release notes.
- `scripts/publish.sh`: downloads each app's newest release APK, updates the listings, signs the
  index and replaces `gh-pages`. Both apps' release scripts run it after a release. See its
  `--help`.

## License

The apps are GPL-3.0-or-later; see their repositories.
