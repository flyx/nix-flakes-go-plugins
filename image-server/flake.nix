{
  description = "demo image server";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    flake-utils.url = github:numtide/flake-utils;
    nix-filter.url = github:numtide/nix-filter;
    api.url = path:../api;
  };
  outputs = {self, nixpkgs, flake-utils, nix-filter, api}:
  let
    buildApp = { pkgs, vendorSha256, plugins ? [] }:
      let
        requireFlake = modName: ''
          require ${modName} v0.0.0
          replace ${modName} => ./vendor-nix/${modName}
        '';
        vendorFlake = modName: src: ''
          mkdir -p $(dirname vendor-nix/${modName})
          cp -r ${src} vendor-nix/${modName}
        '';
        sources = pkgs.stdenvNoCC.mkDerivation {
          name = "image-server-with-plugins-source";
          src = nix-filter.lib.filter {
            root = ./.;
            exclude = [ ./flake.nix ./flake.lock ];
          };
          nativeBuildInputs = plugins;
          phases = [ "unpackPhase" "buildPhase" "installPhase" ];
          PLUGINS_GO = import ./plugins.go.nix pkgs plugins;
          GO_MOD_APPEND = builtins.concatStringsSep "\n"
            ((builtins.map (p: requireFlake p.goPlugin.goModName) plugins)
            ++ [(requireFlake "example.com/api")]);
          buildPhase = ''
            mkdir vendor-nix
            ${builtins.concatStringsSep "\n"
              ((builtins.map (p: vendorFlake p.goPlugin.goModName "${p}/src") plugins)
              ++ [(vendorFlake "example.com/api" api.src)])}
            printenv PLUGINS_GO >plugins.go
            echo "" >>go.mod # newline
            printenv GO_MOD_APPEND >>go.mod
          '';
          installPhase = ''
            mkdir -p $out/src
            cp -r -t $out/src *
          '';
        };
      in pkgs.buildGoModule rec {
        name = "image-server";
        src = builtins.trace "sources at ${sources}" sources;
        modRoot = "src";
        subPackages = [ "." ];
        inherit vendorSha256;
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.cairo ];
        preBuild = ''
          export PATH=$PATH:${pkgs.lib.makeBinPath buildInputs}
        '';
      };
  in (flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      packages.app = buildApp {
        inherit pkgs;
        vendorSha256 = "sha256-yII94225qx8EAMizoPA9BSRP9lz0JL/UoPDNYROcvNw=";
      };
      defaultPackage = packages.app;
    }
  )) // {
    lib = {
      inherit buildApp;
      pluginMetadata = goModFile: {
        goModName = with builtins; head
          (match "module ([^[:space:]]+).*" (readFile goModFile));
      };
    };
  };
}