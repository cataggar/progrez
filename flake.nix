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
        zigTarget = if pkgs.stdenv.isLinux then "${system}-gnu"
          else pkgs.lib.replaceStrings [ "darwin" ] [ "macos" ] system;
        testRunner = pkgs.lib.optionalString pkgs.stdenv.isLinux
          "${pkgs.lib.getLib pkgs.stdenv.cc.libc}/lib/${
            if system == "aarch64-linux"
            then "ld-linux-aarch64.so.1"
            else "ld-linux-x86-64.so.2"
          } --library-path ${pkgs.lib.getLib pkgs.stdenv.cc.libc}/lib";

        progrez = pkgs.stdenv.mkDerivation {
          pname = "progrez";
          version = "0.1.0";
          src = self;

          nativeBuildInputs = [ zig ];
          dontConfigure = true;

          buildPhase = ''
            export HOME="$TMPDIR"
            export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
            zig build -j2 --prefix $out -Dtarget=${zigTarget} -Dcpu=${zigCpu} -Doptimize=fast
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

            nativeBuildInputs = [ zig ];
            dontConfigure = true;

            buildPhase = ''
              export HOME="$TMPDIR"
              export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
              zig build -j2 test-compile -Dtarget=${zigTarget} -Dcpu=${zigCpu} -Doptimize=debug
              # The FHS interpreter is absent in the Nix sandbox. Use libc's
              # runtime loader directly, without rewriting artifacts or caches.
              ${testRunner} zig-out/test-bins/unit_test
              ${testRunner} zig-out/test-bins/ffi-static
              ${testRunner} zig-out/test-bins/ffi-shared
              bash tests/cli/test_cli.sh ${testRunner}
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
