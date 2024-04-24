#!/usr/bin/env nix-shell
#!nix-shell -i nu -p nushell common-updater-scripts prefetch-npm-deps nix-prefetch-github
#
# run without argument to fetch latest, or specify version

def main [version?: string] {
  let sourceFile = $"(pwd)/pkgs/by-name/fo/forgejo/source.json"

  let latest_version = if $version == null {
     list-git-tags --url=https://codeberg.org/forgejo/forgejo | lines | sort --natural | find --invert --regex '(dev|rc)' | str replace 'v' '' | last
  } else {
    $version
  }

  let current_version = if ($sourceFile | path exists) { open $sourceFile | get version } else { "0" }

  if $latest_version != $current_version {
    print ":: getting source repo"
    let source = nix-prefetch-git https://codeberg.org/forgejo/forgejo.git --rev $"v($latest_version)" | from json | merge { version: $latest_version, npmDepsHash: "", vendorHash: ""}
    $source | save --force $sourceFile

    let srcPath = nix-build $env.PWD -A forgejo.src

    print $srcPath

    print ":: getting goModules vendorHash"
    let vendorHash = nix-prefetch -I $"nixpkgs=(pwd)" $"{ sha256 }: \(import (pwd) {}).forgejo.goModules"
    print ":: getting frontend npmsDepsHash"
    let npmDepsHash = prefetch-npm-deps $"($srcPath)/package-lock.json"

    $source | merge {
      npmDepsHash: $npmDepsHash,
      vendorHash: $vendorHash,
    } | save --force $sourceFile

    # appease the editorconfig CI check
    echo "\n" | save --append $sourceFile
  }

  {before: $current_version, after: $latest_version}
}
