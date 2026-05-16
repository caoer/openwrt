{
  description = "OpenWrt build environment for GL-MT3600BE (patched mt76)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              # OpenWrt buildroot host dependencies
              gnumake
              gcc
              binutils
              patch
              bzip2
              flex
              bison
              pkg-config
              unzip
              gawk
              gettext
              ncurses
              zlib
              openssl
              python3
              perl
              wget
              rsync
              file
              which

              # Useful for working with the build
              git
              jq
            ];

            shellHook = ''
              echo "OpenWrt build environment for GL-MT3600BE"
              echo "  nix/config/seed.config — build config (diffconfig format)"
              echo "  nix/files/             — baked-in UCI config overlay"
              echo ""
              echo "Commands:"
              echo "  just setup     — install feeds + apply seed config"
              echo "  just build     — full firmware build"
              echo "  just flash IP  — upload + fire-and-forget sysupgrade"
              echo ""
            '';
          };
        }
      );
    };
}
