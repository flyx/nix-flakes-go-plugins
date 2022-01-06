{
  description = "simple plugin";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    flake-utils.url = github:numtide/flake-utils;
    nix-filter.url = github:numtide/nix-filter;
    mainapp.url = path:../mainapp;
    mainapp.inputs = {
      nixpkgs.follows = "nixpkgs";
      flake-utils.follows = "flake-utils";
      nix-filter.follows = "nix-filter";
    };
  };
  outputs = {self, nixpkgs, flake-utils, nix-filter, mainapp}:
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      packages = rec {
        plugin = pkgs.stdenvNoCC.mkDerivation {
          pname = "mainapp-plugin-simple";
          version = "0.1.0";
          src = nix-filter.lib.filter {
            root = ./.;
            exclude = [ ./flake.nix ./flake.lock ];
          };
          passthru.goPlugin = mainapp.lib.pluginMetadata ./go.mod;
          phases = [ "unpackPhase" "installPhase" ];
          installPhase = ''
            mkdir -p $out/src
            cp -r -t $out/src *
          '';
        };
        app = mainapp.lib.buildApp {
          inherit pkgs;
          vendorSha256 = "sha256-PQyYXVGDETUxEsTT50TSyu/Tv+RQVhplSDFGw8ASpCw=";
          plugins = [ plugin ];
        };
      };
      defaultPackage = packages.app;
    }
  );
}