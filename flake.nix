{
  description = "The Codeg multi-agent coding workspace packaged for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = {
          default = pkgs.callPackage ./package.nix { };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nil
            nixfmt
            statix
          ];
        };
      }
    )
    // {
      homeManagerModules = {
        default = import ./module.nix { inherit self; };
      };
    };
}
