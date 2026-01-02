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

        naersk-package = pkgs.callPackage naersk {
          cargo = rust-toolchain;
          rustc = rust-toolchain;
          clippy = rust-toolchain;
        };

        crane-package = craneLib.buildPackage {
          src = craneLib.cleanCargoSource ./.;
          strictDeps = true;

          cargoExtraArgs = "--target ${buildTarget}";

          buildInputs = with pkgs; [
            pkgsCross.avr.buildPackages.gcc
            ravedude
          ];
        };
      in
      {
        devShells.default = craneLib.devShell {
          packages = with pkgs; [ ];

          RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";

          shellHook = '''';

        };

        packages.default = crane-package;

        apps.default = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "flash-firmware" ''
            ${crane-package}/bin/cargo run
          '';
        };

        formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
      }
    );
}
