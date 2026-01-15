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

        src = craneLib.cleanCargoSource ./.;

        commonArgs = rec {
          inherit src;
          strictDeps = true;

          doCheck = false;

          cargoVendorDir = craneLib.vendorMultipleCargoDeps {
            inherit (craneLib.findCargoFiles src) cargoConfigs;
            cargoLockList = [
              ./Cargo.lock
              ./toolchain/Cargo.lock
            ];
          };

          buildInputs = with pkgs; [
            pkgsCross.avr.buildPackages.gcc
          ];

          cargoExtraArgs = ''
            --release -Z build-std=core -vv
          '';

          buildPhaseCargoCommand = ''
            cargo build ${cargoExtraArgs}
          '';

          env = {
            CARGO_BUILD_TARGET = "${buildTarget}";
            CARGO_BUILD_INCREMENTAL = "false";
            RUSTFLAGS = "-C target-cpu=atmega328p -C panic=abort";
            # CARGO_TARGET_AVR_NONE_LINKER = "${pkgs.pkgsCross.avr.buildPackages.gcc}/bin/avr-gcc";
            CARGO_TARGET_AVR_NONE_LINKER = "${pkgs.pkgsCross.avr.stdenv.cc}/bin/${pkgs.pkgsCross.avr.stdenv.cc.targetPrefix}cc";
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
            inherit cargoArtifacts;

            doNotPostBuildInstallCargoBinaries = true;

            installPhaseCommand = ''
              mkdir -p $out/bin

              cp ./target/avr-none/release/blinkyy.elf $out/bin/binary.elf
            '';

          }
        );

        flash-firmware = pkgs.writeShellApplication {
          name = "blinkyy";

          runtimeInputs = with pkgs; [
            ravedude
          ];

          text = ''
            ravedude -c -b 57600 ${crane-package}/bin/binary.elf
          '';
        };

      in
      {
        devShells.default = pkgs.mkShell {
          # Inherits buildInputs from crane-package
          inputsFrom = [ crane-package ];

          # Additional packages
          packages = with pkgs; [
            rust-toolchain
            cargo-cache
            # cargo-nono
          ];

          env = {
            CARGO_BUILD_TARGET = "avr-none";
            RUST_SRC_PATH = "${rust-toolchain}/lib/rustlib/src/rust/library";
          };

          shellHook = '''';

        };

        apps.updateSrc = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "update-rust-src-lockfile" ''
            cp "${rust-toolchain}"/lib/rustlib/src/rust/library/Cargo.lock ./toolchain/.
          '';
        };

        packages.default = flash-firmware;

        formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
      }
    );
}
