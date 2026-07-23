{
  description = "of-the-star's custom arduino rust development flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    crane = {
      url = "github:ipetkov/crane";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      rust-overlay,
    }:
    let
      systems = [
        "x86_64-linux"
      ];
      iterOverSystems = nixpkgs.lib.genAttrs systems;
      forSystem =
        system:
        let
          buildTarget = "avr-none";

          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };

          # Imports custom toolchain, or falls back to default for AVR projects
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
          pname = (craneLib.crateNameFromCargoToml { cargoToml = ./Cargo.toml; }).pname;

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
                (./toolchain/Cargo.lock)
              ];
            };

            buildInputs = with pkgs; [
              pkgsCross.avr.buildPackages.gcc
              ravedude
            ];

            # '-Z build-std=core' is required because precompiled artifacts aren't available for the 'avr-none' target
            cargoExtraArgs = ''
              --release -Z build-std=core
            '';

            # Skips Crane's default 'cargo check' step since the 'avr-none' target is a 'no_std' environment
            buildPhaseCargoCommand = ''
              cargo build ${cargoExtraArgs}
            '';

            env = {
              CARGO_BUILD_TARGET = "${buildTarget}";
              RUSTFLAGS = "-C target-cpu=atmega328p -C panic=abort";
              CARGO_TARGET_AVR_NONE_LINKER = "${pkgs.pkgsCross.avr.stdenv.cc}/bin/${pkgs.pkgsCross.avr.stdenv.cc.targetPrefix}cc";
            };
          };

          # Lets us reuse artifacts from the project dependencies
          cargoArtifacts = craneLib.buildDepsOnly (
            commonArgs
            // {
              # Works around Crane's opinionated dummy source, which doesn't work with the 'no_std' and 'no_main' modifiers
              dummyBuildrs = pkgs.writeText "build.rs" "fn main () { }";
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

          package = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;

              # We manage the installation of the resulting binary ourselves
              doNotPostBuildInstallCargoBinaries = true;
              installPhaseCommand = ''
                mkdir -p $out/bin
                cp ./Ravedude.toml $out/.
                cp ./target/${buildTarget}/release/*.elf $out/bin/.
              '';
            }
          );

          # Create a shell script to use Ravedude to flash the binary so that we can flash it with `nix run`
          flashFirmware = pkgs.writeShellApplication {
            name = pname;
            runtimeInputs = with pkgs; [
              avrdude
              pkgsCross.avr.buildPackages.gcc
              ravedude
            ];
            text = ''
              CARGO_MANIFEST_DIR=${package} ravedude ${package}/bin/*.elf
            '';
          };

          # Shell script invoked via `nix run .#updateSrc` to keep the 'core' library lockfile up to date
          # TODO: Make this more automatic while avoiding IFD
          updateSrc = pkgs.writeShellApplication {
            name = "updateSrc";
            text = ''
              cp "${rust-toolchain}"/lib/rustlib/src/rust/library/Cargo.lock ${src}/toolchain/Cargo.lock
            '';
          };
        in
        {
          inherit
            package
            ;

          "${pname}" = package;

          devShell = pkgs.mkShell {
            # Inherits buildInputs from `package`
            inputsFrom = [ package ];

            # Additional packages for the dev environment
            packages = with pkgs; [
              cargo-cache
              just
            ];

            shellHook = "";

            env = {
              CARGO_BUILD_TARGET = "${buildTarget}";
              # Needed for rust-analyzer
              RUST_SRC_PATH = "${rust-toolchain}/lib/rustlib/src/rust/library";
            };
          };

          apps = {
            "flashFirmware" = {
              type = "app";
              program = "${flashFirmware}/bin/${flashFirmware.name}";
            };
            "updateSrc" = {
              type = "app";
              program = "${updateSrc}/bin/${updateSrc.name}";
            };
          };

          formatter = pkgs.nixfmt-tree;
        };
    in
    {
      devShells = (
        iterOverSystems (system: {
          default = (forSystem system).devShell;
        })
      );

      formatter = (iterOverSystems (system: (forSystem system).formatter));

      packages = (
        iterOverSystems (system: {
          default = (forSystem system).package;
        })
      );

      apps = (
        iterOverSystems (
          system:
          let
            apps = (forSystem system).apps;
          in
          {
            inherit (apps) updateSrc;
            default = apps.flashFirmware;
          }
        )
      );
    };
}
