{ callPackage }:
callPackage ./release.nix { } // callPackage ./library-paths.nix { }
