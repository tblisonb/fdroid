#!/usr/bin/env bash
# Usage: scripts/publish.sh
#
# Brings the F-Droid repo (https://tblisonb.github.io/fdroid/repo) up to date with the GitHub
# releases of Segue and MediaSync:
#   1. downloads the APK of each app's newest release, if it isn't in repo/ yet;
#   2. writes its "What's new" (metadata/<app>/en-US/changelogs/<versionCode>.txt) from the
#      release notes, and commits and pushes that to main;
#   3. runs fdroid update, which signs the index with the repo key;
#   4. publishes repo/ to the gh-pages branch, which GitHub Pages serves. The branch is one commit,
#      replaced each time, so old APKs don't pile up in git.
#
# The APKs are the releases' own, signed with the apps' release key, so they install over (and are
# updated by) copies installed from GitHub. Only the newest 3 versions of each app stay in the repo.
# The release scripts of both apps run this after a release; run it yourself to retry.
#
# Needs: gh, logged in; fdroidserver (pipx install fdroidserver, then pipx inject fdroidserver
# 'setuptools<81'); the Android SDK; and the repo key, ~/.android/fdroid-repo.p12 with its passwords
# in ~/.android/fdroid-repo.properties. Back both up: without them, phones would have to remove the
# repo and add it again (under a new key).
set -euo pipefail
# -h or --help prints the comment at the top of this file.
for arg in "$@"; do
    [[ $arg != -h && $arg != --help ]] || { awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0; }
done
cd "$(dirname "$0")/.."

# GitHub repo, package name, and the APK's name in its releases (a regex).
apps=(
    "tblisonb/Segue com.tlisonbee.segue ^segue-.*\\.apk$"
    "tblisonb/MediaSync com.tlisonbee.mediasync ^mediasync-.*\\.apk$"
)
pages_url=https://github.com/tblisonb/fdroid.git

export JAVA_HOME=${JAVA_HOME:-$HOME/Android/jdk-21}
export PATH=$JAVA_HOME/bin:$HOME/.local/bin:$PATH
aapt2=$(ls -d "$HOME"/Android/Sdk/build-tools/*/aapt2 | sort -V | tail -1)
props=$HOME/.android/fdroid-repo.properties
# fdroid update makes the key on the very first run; after that, it must be the same key.
if [[ ! -f $props || ( ! -f $HOME/.android/fdroid-repo.p12 && -n $(git ls-remote "$pages_url" gh-pages) ) ]]; then
    echo "No repo key: restore ~/.android/fdroid-repo.{p12,properties} from your backup." >&2
    exit 1
fi
# Read without evaluating: the passwords have characters a shell would interpret.
while IFS= read -r line; do
    [[ $line == FDROID_*=* ]] && export "${line%%=*}=${line#*=}"
done < "$props"
chmod 600 config.yml

[[ $(git rev-parse --abbrev-ref HEAD) == main ]] || { echo "Publish from main." >&2; exit 1; }
git pull -q --ff-only origin main

mkdir -p repo
for app in "${apps[@]}"; do
    read -r gh_repo package pattern <<<"$app"
    release=$(gh api "repos/$gh_repo/releases" | jq --arg p "$pattern" '[.[] | select(.draft or .prerelease | not)
        | select(any(.assets[]; .name | test($p)))][0]')
    [[ -n $release && $release != null ]] || { echo "$gh_repo has no release with an APK." >&2; exit 1; }
    tag=$(jq -r .tag_name <<<"$release")
    asset=$(jq -r --arg p "$pattern" '[.assets[] | select(.name | test($p))][0].name' <<<"$release")
    if [[ ! -f repo/$asset && ! -f archive/$asset ]]; then
        echo "Adding $asset ($gh_repo $tag)"
        # Into tmp/ first, so a download that's cut off doesn't leave half an APK in repo/.
        rm -rf tmp/download && mkdir -p tmp/download
        gh release download "$tag" -R "$gh_repo" -p "$asset" -D tmp/download
        mv "tmp/download/$asset" repo/
    fi
    [[ -f repo/$asset ]] || continue
    code=$("$aapt2" dump badging "repo/$asset" | sed -n "s/^package: .* versionCode='\([0-9]*\)'.*/\1/p")
    changelog=metadata/$package/en-US/changelogs/$code.txt
    if [[ ! -f $changelog ]]; then
        # F-Droid shows plain text, at most 500 characters: whole lines, up to that.
        mkdir -p "$(dirname "$changelog")"
        jq -r .body <<<"$release" | sed -E 's/\*\*//g; s/`//g; s/\[([^]]*)\]\([^)]*\)/\1/g; s/^#+ *//' |
            awk '{ n += length($0) + 1 } n > 490 { print "…"; exit } { print }' > "$changelog"
    fi
done

if [[ -n $(git status --porcelain metadata) ]]; then
    git add metadata
    git commit -q -m "What's new for the latest releases"
    git push -q origin main
fi

fdroid update --use-date-from-apk

# The page at https://tblisonb.github.io/fdroid/: how to add the repo.
# F-Droid's fingerprint of a repo: the SHA-256 of its signing certificate.
fingerprint=$(keytool -list -v -keystore "$HOME/.android/fdroid-repo.p12" -storepass:env FDROID_KEYSTORE_PASS \
    -alias tblisonb-fdroid | sed -n 's/^\s*SHA256: //p' | tr -d ':' | tr 'A-F' 'a-f')
[[ ${#fingerprint} == 64 ]] || { echo "Couldn't read the repo key's fingerprint." >&2; exit 1; }
add_url="https://tblisonb.github.io/fdroid/repo?fingerprint=$fingerprint"

pages=$(mktemp -d)
trap 'rm -rf "$pages"' EXIT
cp -r repo "$pages/repo"
touch "$pages/.nojekyll"
cat > "$pages/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>tblisonb's F-Droid repo</title></head>
<body style="font-family: sans-serif; max-width: 40em; margin: 2em auto; padding: 0 1em; line-height: 1.5">
<h1>tblisonb's F-Droid repo</h1>
<p><a href="https://github.com/tblisonb/Segue">Segue</a> and
<a href="https://github.com/tblisonb/MediaSync">MediaSync</a>, the same APKs as their GitHub releases.</p>
<p>On your phone, <a href="fdroidrepos://tblisonb.github.io/fdroid/repo?fingerprint=$fingerprint">open this link</a>
in F-Droid, or add this repo by hand in F-Droid's Settings &gt; Repositories:</p>
<p><code style="word-break: break-all">$add_url</code></p>
<p>Fingerprint of the repo's signing key:<br><code style="word-break: break-all">$fingerprint</code></p>
</body>
</html>
EOF
git -C "$pages" init -q -b gh-pages
git -C "$pages" add -A
git -C "$pages" commit -q -m "F-Droid repo, $(date -u +%Y-%m-%d)"
git -C "$pages" push -q -f "$pages_url" gh-pages
echo "Published: $add_url"
