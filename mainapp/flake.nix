{
  description = "main application";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    utils.url = github:numtide/flake-utils;
    nix-filter.url = github:numtide/nix-filter;
  };
  outputs = {self, nixpkgs, utils, nix-filter }:
  let
    buildApp = { system, vendorSha256, plugins ? [] }:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        requirePlugin = modName: ''
          require ${modName} v0.0.0
          replace ${modName} => ./vendor-nix/${modName}
        '';
        vendorFlake = modName: src: ''
          mkdir -p $(dirname vendor-nix/${modName})
          cp -r ${src} vendor-nix/${modName}
        '';
        sources = pkgs.stdenvNoCC.mkDerivation {
          name = "mainapp-with-plugins-source";
          src = nix-filter.lib.filter {
            root = ./.;
            exclude = [ ./flake.nix ./flake.lock ];
          };
          phases = [ "unpackPhase" "buildPhase" "installPhase" ];
          PLUGINS_GO = import ./plugins.go.nix plugins;
          GO_MOD_APPEND = builtins.concatStringsSep "\n"
            (builtins.map (p: requirePlugin p.goPlugin.goModName)
             plugins);
          buildPhase = ''
            mkdir vendor-nix
            ${builtins.concatStringsSep "\n"
              (builtins.map (p: vendorFlake p.goPlugin.goModName
               "${p}/src") plugins)}
            printenv PLUGINS_GO >plugins.go
            echo "" >>go.mod # newline
            printenv GO_MOD_APPEND >>go.mod
          '';
          installPhase = ''
            mkdir -p $out/src
            cp -r -t $out/src *
          '';
        };
      in pkgs.buildGoModule {
        name = "mainapp";
        src = sources;
        modRoot = "src";
        subPackages = [ "." ];
        inherit vendorSha256;
      };
  in (utils.lib.eachDefaultSystem (system: rec {
    packages.app = buildApp {
      inherit system;
      vendorSha256 = "pQpattmS9VmO3ZIQUFn66az8GSmB4IvYhTTCFn6SUmo=";
    };
    defaultPackage = packages.app;
  })) // {
    lib = {
      inherit buildApp;
      pluginMetadata = goModFile: {
        goModName = with builtins; head
          (match "module ([^[:space:]]+).*" (readFile goModFile));
      };
    };
  };
}
