{
  description = "progrez - unified progress indication library for CLI tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        zig = zig-overlay.packages.${system}."0.17.0";
        zigCpu = "baseline";

        progrez = pkgs.stdenv.mkDerivation {
          pname = "progrez";
          version = "0.1.0";
          src = self;

          nativeBuildInputs = [ zig ];
          dontConfigure = true;

          buildPhase = ''
            export HOME="$TMPDIR"
            export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
            zig build -j2 --prefix $out -Dcpu=${zigCpu} -Doptimize=fast
          '';

          dontInstall = true;
        };
      in {
        packages.default = progrez;

        checks = {
          test = pkgs.stdenv.mkDerivation {
            pname = "progrez-test";
            version = "0.1.0";
            src = self;

            nativeBuildInputs = [ zig ]
              ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.patchelf ];
            dontConfigure = true;

            buildPhase = ''
              export HOME="$TMPDIR"
              export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
              zig build -j2 test-compile -Dcpu=${zigCpu} -Doptimize=debug
              # Zig with link_libc bakes /lib64/ld-linux-x86-64.so.2 as the
              # dynamic linker, which does not exist in the Nix build sandbox.
              # Patch only installed executables, leaving build caches intact.
              ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              DL="$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)"
              for f in zig-out/bin/* zig-out/test-bins/*; do
                patchelf --set-interpreter "$DL" "$f"
              done
              ''}
              zig-out/test-bins/unit_test
              zig-out/test-bins/ffi-static
              zig-out/test-bins/ffi-shared
              bash tests/cli/test_cli.sh
            '';

            installPhase = ''
              touch $out
            '';
          };
        } // pkgs.lib.optionalAttrs
          (pkgs.stdenv.isLinux && pkgs.stdenv.hostPlatform.isx86_64) {
            package-reproducibility = pkgs.runCommand "progrez-package-reproducibility" {
              nativeBuildInputs = [ pkgs.binutils ];
            } ''
              ${pkgs.bash}/bin/bash ${./tests/reproducibility/test_package_classifier} \
                ${./tests/reproducibility/check_package_reproducibility} \
                ${pkgs.bash}/bin/bash \
                ${pkgs.binutils}/bin/as \
                ${pkgs.binutils}/bin/ar \
                ${pkgs.binutils}/bin/objdump
              ${pkgs.bash}/bin/bash ${./tests/reproducibility/check_package_reproducibility} \
                ${progrez} \
                ${pkgs.binutils}/bin/objdump
              touch $out
            '';
          };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            zig
            pkgs.hyperfine
          ];

          shellHook = ''
            echo "progrez dev shell"
            echo "  zig: $(zig version)"
          '';
        };
      }
    );
}
