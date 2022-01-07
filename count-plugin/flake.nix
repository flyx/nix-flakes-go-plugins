{
  description = "count plugin for image-server";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    flake-utils.url = github:numtide/flake-utils;
    nix-filter.url = github:numtide/nix-filter;
    image-server.url = path:../image-server;
    image-server.inputs = {
      nixpkgs.follows = "nixpkgs";
      flake-utils.follows = "flake-utils";
      nix-filter.follows = "nix-filter";
    };
  };
  outputs = {self, nixpkgs, flake-utils, nix-filter, image-server}:
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      packages = rec {
        plugin = pkgs.stdenvNoCC.mkDerivation {
          pname = "image-server-count-plugin";
          version = "0.1.0";
          src = nix-filter.lib.filter {
            root = ./.;
            exclude = [ ./flake.nix ./flake.lock ];
          };
          passthru.goPlugin = image-server.lib.pluginMetadata ./go.mod;
          phases = [ "unpackPhase" "buildPhase" "installPhase" ];
          buildPhase = ''
            echo "\nrequire example.com/api v0.0.0" >>go.mod
          '';
          installPhase = ''
            mkdir -p $out/src
            cp -r -t $out/src *
          '';
        };
        app = image-server.lib.buildApp {
          inherit system;
          vendorSha256 = "sha256-US38BDmwhrrMxvZVzEq1ch65DGDS6Mq/IO4NvgyHsQU=";
          plugins = [ plugin ];
        };
      };
      defaultPackage = packages.app;
    }
  );
}