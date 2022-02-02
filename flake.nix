{
  description = "Article 'Exploring Nix Flakes: Usable Go Plugins'";
  
  inputs = {
    nixpkgs.url = github:nixos/nixpkgs/21.11;
    utils.url = github:numtide/flake-utils;
    nix-filter.url = github:numtide/nix-filter;
  };
  
  outputs = { self, nixpkgs, utils, nix-filter }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in rec {
        packages = rec {
          # I use this in the build of my homepage.
          sources = nix-filter.lib.filter {
            root = ./.;
            exclude = [ ./flake.nix ./flake.lock ./testing ./Readme.md ];
          };
          # starts a jekyll server at localhost:4000 to check that everything
          # renders properly
          testServer = pkgs.stdenvNoCC.mkDerivation rec {
            name = "testServer";
            phases = [ "unpackPhase" "buildPhase" "installPhase" ];
            src = nix-filter.lib.filter {
              root = ./.;
              exclude = [ ./flake.nix ./flake.lock ./Readme.md ];
            };
            propagatedBuildInputs = [ pkgs.coreutils pkgs.jekyll ];
            SCRIPT = ''
              DIR=$(${pkgs.coreutils}/bin/mktemp -d)
              cd ${builtins.placeholder "out"}/share
              ${pkgs.jekyll}/bin/jekyll serve --disable-disk-cache -d "$DIR"
            '';
            buildPhase = ''
              mv testing/* .
              rmdir testing
            '';
            installPhase = ''
              mkdir -p $out/{bin,share}
              printenv SCRIPT >$out/bin/testServer
              chmod u+x $out/bin/testServer
              cp -r * $out/share/
            '';
          };
        };
        defaultPackage = packages.testServer;
      });
}