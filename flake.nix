{
  description = "of-the-star's custom arduino development flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk/master";
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
      naersk,
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
        # crane-package = craneLib.buildPackage {
        #   src = craneLib.cleanCargoSource ./.;
        #   strictDeps = false;
        #   doCheck = false;
        #   cargoArtifacts = if builtins.pathExists ./target then ./target else null;
        #   buildPhaseCargoCommand = "cargo build --profile release";
        #   doInstallCargoArtifacts = true;
        #
        #   NIX_DEBUG = 5;
        #
        #   # cargoArtifacts = null;
        #   cargoExtraArgs = "--target ${buildTarget}";
        #
        #   buildInputs = with pkgs; [
        #     pkgsCross.avr.buildPackages.gcc
        #     ravedude
        #   ];
        #
        #   # preBuild = ''
        #   #   export CARGO_PROFILE_RELEASE_OPT_LEVEL="s"
        #   #   export CARGO_PROFILE_RELEASE_DEBUG="true"
        #   #   export CARGO_PROFILE_RELEASE_LTO="true"
        #   #   export CARGO_PROFILE_RELEASE_PANIC="abort"
        #   #   export CARGO_PROFILE_RELEASE_CODEGEN_UNITS="1"
        #   # '';
        #
        #   configureCargoCommonVars = '''';
        #   configurePhase = '''';
        #   checkPhaseCargoCommand = ''
        #     echo hiiiiii!!!
        #   '';
        #
        #   preBuild = ''
        #     # ${pkgs.bat}/bin/bat -pp /build/source/.cargo-home/config.toml
        #   '';
        #
        #   installPhase = ''
        #     runHook preInstall
        #
        #     mkdir -p $out/bin
        #     cp target/avr-none/release/blinkyy.elf $out/bin
        #
        #     runHook postInstall
        #   '';
        # };

        # crane-package = craneLib.mkCargoDerivation {
        #   src = craneLib.cleanCargoSource ./.;
        #   cargoArtifacts = craneLib.buildDepsOnly rec {
        #     src = craneLib.cleanCargoSource ./.;
        #     cargoExtraArgs = "--target ${buildTarget}";
        #     buildPhaseCargoCommand = ''
        #       ${cargoBuildCommand} ${cargoExtraArgs}
        #     '';
        #     cargoBuildCommand = ''cargo build --release'';
        #     doCheck = false;
        #   };
        #
        #   checkPhase = '''';
        #   buildPhaseCargoCommand = ''
        #     cargo build --release --target avr-none --config ./.cargo/config.toml
        #   '';
        # };

        naerskLib = pkgs.callPackage naersk {
          cargo = rust-toolchain;
          rustc = rust-toolchain;
        };

        naersk-package = naerskLib.buildPackage {
          src = ./.;

          copyTarget = true;
          singleStep = true;

          cargoBuildOptions =
            opts:
            opts
            ++ [
              # "--release"
              ''--target ${buildTarget}''
              "-vv"
              ''--config 'build.rustflags=["-C", "target-cpu=atmega328p"]' ''
              ''--config profile.release.opt-level=\"s\" ''
              ''--config profile.release.debug=true''
              ''--config profile.release.lto=true''
              ''--config profile.release.codegen-units=1''
              ''--config profile.release.panic=\"abort\"''
              "--keep-going"
            ];

          CARGO_INCREMENTAL = 0;

          buildInputs = with pkgs; [
            ravedude
            rust-toolchain
          ];

          nativeBuildInputs = with pkgs; [
            pkgsCross.avr.gcc
          ];
        };

      in
      {
        devShells.default = pkgs.mkShell {
          # Inherits buildInputs from crane-package
          # inputsFrom = [ crane-package ];

          # Additional packages
          packages = with pkgs; [
            pkgsCross.avr.buildPackages.gcc
            ravedude
            rust-toolchain
            cargo-cache
          ];

          RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";

          shellHook = '''';

        };

        apps.default = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "flash-firmware" ''
            ${pkgs.ravedude}/bin/ravedude -c -b 57600 $out/bin
          '';

          # drv = crane-package;
        };

        packages.default = naersk-package;
        # packages.default = crane-package;

        # checks = { inherit crane-package; };

        formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
      }
    );
}
