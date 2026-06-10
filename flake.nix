{
  description = "OpenWrt build environment for GL-MT3600BE (patched mt76)";
  # NOTE: devShell provides host deps for fresh machines only.
  # Do NOT mix nix develop with an existing native build_dir —
  # the different host toolchain will segfault cached binaries.
  # On machines with build-essential already installed, run `just build` directly.

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
            # OpenWrt buildroot manages its own flags; nix cc-wrapper hardening
            # (-Werror=format-security etc.) breaks host tools like elfutils.
            hardeningDisable = [ "all" ];

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
              # nix stdenv exports toolchain env vars that leak into cross
              # builds (TF-A reads AS and assembles with raw 'as' + gcc
              # flags). OpenWrt buildroot sets its own toolchain vars.
              unset AS LD AR NM RANLIB STRIP OBJCOPY OBJDUMP SIZE

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
