{
  description = "of-the-star's custom arduino development flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      crane,
      rust-overlay,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        buildTarget = "avr-none";

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        rust-toolchain =
          if builtins.pathExists ./rust-toolchain.toml then
            pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml
          else
            pkgs.rust-bin.selectLatestNightlyWith (
              toolchain:
              toolchain.minimal.override {
                extensions = [ "rust-src" ];
              }
            );

        craneLib = (crane.mkLib pkgs).overrideToolchain rust-toolchain;

        cleanedSrc = pkgs.lib.cleanSourceWith {
          src = craneLib.path ./.;
          filter = path: type: (craneLib.filterCargoSources path type) || (pkgs.lib.hasInfix ".cargo" path);
        };

        commonArgs = rec {
          src = cleanedSrc;
          strictDeps = true;

          doCheck = false;

          buildInputs = with pkgs; [
            pkgsCross.avr.buildPackages.gcc
            pkgsCross.avr.buildPackages.libc
          ];

          cargoExtraArgs = ''
            --locked -Z build-std=core
          '';
          cargoCheckExtraArgs = ''
            --target ${buildTarget} -Z build-std=core -Z build-std-features=""
          '';

          buildPhaseCargoCommand = ''
            cargo build ${cargoExtraArgs}
          '';

          uselessExtraArgs = ''
            --config profile.release.panic=\"abort\" --config 'build.rustflags=["-C", "target-cpu=atmega328p", "-C","panic=abort"]' --config 'target.avr-none.rustflags=["-C", "target-cpu=atmega328p", "-C","panic=abort"]'
          '';

          env = {
            CARGO_BUILD_TARGET = "${buildTarget}";
            RUSTCFLAGS = "-C panic=abort";
            # CARGO_HOME = "/build/source/.cargo";
            # CARGO_BUILD_INCREMENTAL = "false";
            # CARGO_LOG = "cargo::core::compiler::fingerprint=trace,cargo_util::paths=trace";
          };
        };

        cargoArtifacts = craneLib.buildDepsOnly (
          commonArgs
          // {
            dummyBuildrs = pkgs.writeText "build.rs" ''
              fn main() {
                // println!("cargo::rustc-env=RUSTFLAGS=-C target-cpu=atmega328p -C panic=abort")
              }
            '';
            dummyrs = pkgs.writeText "dummy.rs" ''
              #![no_main]
              #![no_std]


              use panic_halt as _;

              #[arduino_hal::entry]
              fn main() -> ! {
                loop { }
              }

              // use core::panic::PanicInfo;

              // #[inline(never)]
              // #[panic_handler]
              // fn panic(_info: &PanicInfo) -> ! {
              //     loop {}
              // }

              // #[no_mangle]
              // pub extern "C" fn _start() -> ! {
              //     loop {}
              // }

            '';
          }

        );

        crane-package = craneLib.buildPackage (
          commonArgs
          // {
            # inherit cargoArtifacts;
          }
        );

      in
      {
        devShells.default = pkgs.mkShell {
          # Inherits buildInputs from crane-package
          inputsFrom = [ crane-package ];

          # Additional packages
          packages = with pkgs; [
            rust-toolchain
            cargo-cache
          ];

          env = {
            CARGO_BUILD_TARGET = "avr-none";
            RUST_SRC_PATH = "${rust-toolchain}/lib/rustlib/src/rust/library";
          };

          shellHook = '''';

        };

        apps.default = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "flash-arduino-uno" ''
            ${pkgs.ravedude}/bin/ravedude -c -b 57600 $out/bin
          '';
        };

        packages.default = crane-package;

        formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
      }
    );
}
