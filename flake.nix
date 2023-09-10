{
  description = "Hercules CI Effects";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    hercules-ci-agent.url = "hercules-ci-agent";
    hercules-ci-agent.inputs.nixpkgs.follows = "nixpkgs";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, hercules-ci-agent, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; }
      ({ withSystem, ... }: {
        imports = [
          ./flake-public-outputs.nix
          ./flake-dev.nix
        ];
      });
}
