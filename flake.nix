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
        # Defines package name
        pname = "blinkyy";

        buildTarget = "avr-none";

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        # Imports custom toolchain, or falls back to default
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

        # Instantiates custom craneLib using toolchain
        craneLib = (crane.mkLib pkgs).overrideToolchain rust-toolchain;

        src = craneLib.cleanCargoSource ./.;

        # Common arguments shared between buildPackage and buildDepsOnly
        commonArgs = rec {
          inherit src;
          strictDeps = true;

          doCheck = false;

          # Helps vendor 'core' so that all its dependencies can be found
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

          # '-Z build-std=core' is required because precompiled artifacts aren't available for avr-none
          cargoExtraArgs = ''
            --release -Z build-std=core
          '';

          # Skips 'cargo check' since avr-none is a 'no_std' environment
          buildPhaseCargoCommand = ''
            cargo build ${cargoExtraArgs}
          '';

          env = {
            CARGO_BUILD_TARGET = "${buildTarget}";
            # CARGO_BUILD_INCREMENTAL = "false";
            RUSTFLAGS = "-C target-cpu=atmega328p -C panic=abort";
            CARGO_TARGET_AVR_NONE_LINKER = "${pkgs.pkgsCross.avr.stdenv.cc}/bin/${pkgs.pkgsCross.avr.stdenv.cc.targetPrefix}cc";
          };
        };

        # Lets us reuse artifacts from the project dependencies
        cargoArtifacts = craneLib.buildDepsOnly (
          commonArgs
          // {
            # Works around Crane's opinionated dummy source, which doesn't work with the 'no_std' and 'no_main' modifiers
            dummyBuildrs = pkgs.writeText "build.rs" ''fn main () { }'';
            dummyrs = pkgs.writeText "dummy.rs" ''
              #![no_main]
              #![no_std]


              use panic_halt as _;

              #[arduino_hal::entry]
              fn main() -> ! {
                loop { }
              }
            '';
          }
        );

        crane-package = craneLib.buildPackage (
          commonArgs
          // {
            inherit cargoArtifacts;

            # We manage the installation of the resulting binary ourselves
            doNotPostBuildInstallCargoBinaries = true;
            installPhaseCommand = ''
              mkdir -p $out/bin
              cp ./target/avr-none/release/*.elf $out/bin/binary.elf
            '';
          }
        );

        # We create a shell script to use Ravedude to flash the binary
        flash-firmware = pkgs.writeShellApplication {
          name = pname;
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
            cargo-cache
          ];

          env = {
            CARGO_BUILD_TARGET = "avr-none";
            # Needed for rust-analyzer
            RUST_SRC_PATH = "${rust-toolchain}/lib/rustlib/src/rust/library";
          };
        };

        # Shell script invoked via `nix run .#updateSrc` to keep the 'core' library lockfile up to date
        # TODO: Make this more automatic while avoiding IFD
        apps.updateSrc = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "update-rust-src-lockfile" ''
            cp "${rust-toolchain}"/lib/rustlib/src/rust/library/Cargo.lock ./toolchain/.
          '';
        };

        # Gives us a default package to use 'nix run with'
        packages.default = flash-firmware;

        formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
      }
    );
}
