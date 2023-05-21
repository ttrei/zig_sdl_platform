{
  description = "Handmade Pool dev env";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          bashInteractive
          pkg-config
          libjpeg
          libpng
          libtiff
          libwebp
          SDL2.dev
          SDL2_image
        ];
      };
    });
}
