{
  description = "Nix packaging for BeaverHabits — self-hosted habit tracker (daya0576/beaverhabits)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # uv2nix stack — builds the Python app straight from its uv.lock, so we don't
    # depend on nixpkgs having nicegui>=3.13 / fastapi-users (it doesn't).
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { self, nixpkgs, flake-parts, uv2nix, pyproject-nix, pyproject-build-systems, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];

      perSystem = { pkgs, system, ... }:
        let
          beaverhabits = pkgs.callPackage ./package.nix {
            inherit uv2nix pyproject-nix pyproject-build-systems;
          };
        in {
          packages.beaverhabits = beaverhabits;
          packages.default = beaverhabits;
        };

      flake = {
        nixosModules.beaverhabits = import ./module.nix {
          inherit self uv2nix pyproject-nix pyproject-build-systems;
        };
        nixosModules.default = self.nixosModules.beaverhabits;

        # Overlay exposing `pkgs.beaverhabits`.
        overlays.default = final: prev: {
          beaverhabits = final.callPackage ./package.nix {
            inherit uv2nix pyproject-nix pyproject-build-systems;
          };
        };
      };
    };
}
