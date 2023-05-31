{
  description = "Handmade Pool dev env";
  # inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  # Have to match the NixOS version until this is fixed:
  # https://github.com/ziglang/zig/issues/15898
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/22.11";
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
