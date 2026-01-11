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
        crane-package = craneLib.buildPackage rec {
          src = craneLib.cleanCargoSource ./.;
          strictDeps = true;

          cargoExtraArgs = "--release --target ${buildTarget}";

          buildInputs = with pkgs; [
            pkgsCross.avr.buildPackages.gcc
            ravedude
          ];

          preBuild = ''
            export CARGO_PROFILE_RELEASE_OPT_LEVEL="s"
            export CARGO_PROFILE_RELEASE_DEBUG="true"
            export CARGO_PROFILE_RELEASE_LTO="true"
            export CARGO_PROFILE_RELEASE_PANIC="abort"
            export CARGO_PROFILE_RELEASE_CODEGEN_UNITS="1"
          '';

          buildPhase = ''
            runHook preBuild

            cargo build ${cargoExtraArgs}

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            cp target/avr-none/release/blinkyy.elf $out/bin

            runHook postInstall 
          '';

          # cargoArtifacts = if builtins.pathExists ./target then ./target else null;

          doInstallCargoArtifacts = true;

        };

      in
      {
        devShells.default = craneLib.devShell {
          # Inherits buildInputs from crane-package
          inputsFrom = [ crane-package ];

          # Additional packages
          packages = [ ];

          RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";

          shellHook = '''';

        };

        apps.default = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "flash-firmware" ''
            ${pkgs.ravedude}/bin/ravedude -c -b 57600 $out/bin
          '';

          # drv = crane-package;
        };

        # packages.default = naersk-package;
        packages.default = crane-package;

        # checks = { inherit crane-package; };

        formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
      }
    );
}
