{
  description = "demo image server";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    flake-utils.url = github:numtide/flake-utils;
    nix-filter.url = github:numtide/nix-filter;
    api.url = path:../api;
    zig.url = "github:arqv/zig-overlay";
    zig.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = {self, nixpkgs, flake-utils, nix-filter, api, zig}:
  let
    platforms = system: let
      pkgs = nixpkgs.legacyPackages.${system};
      zigPkg = zig.packages.${system}."0.9.0";
      zigScript = target: command: ''
        #!/bin/sh
        ${zigPkg}/bin/zig ${command} -target ${target} $@
      '';
      zigScripts = target: pkgs.stdenvNoCC.mkDerivation {
        name = "zig-cc-scripts";
        phases = [ "buildPhase" "installPhase" ];
        propagatedBuildInputs = [ zigPkg pkgs.coreutils ];
        ZCC = zigScript target "cc";
        ZXX = zigScript target "c++";
        buildPhase = ''
          printenv ZCC >zcc
          printenv ZXX >zxx
          chmod u+x zcc zxx
        '';
        installPhase = ''
          mkdir -p $out/bin
          cp zcc zxx $out/bin
        '';
      };
      fromDebs = name: debSources: pkgs.stdenvNoCC.mkDerivation rec {
        inherit name;
        srcs = with builtins; map fetchurl debSources;
        phases = [ "unpackPhase" "installPhase" ];
        nativeBuildInputs = [ pkgs.dpkg ];
        unpackPhase = builtins.concatStringsSep "\n" (builtins.map
          (src: "${pkgs.dpkg}/bin/dpkg-deb -x ${src} .") srcs);
        installPhase = ''
          mkdir -p $out
          cp -r * $out
        '';
      };
      fromPacman = name: pacmanSources: pkgs.stdenvNoCC.mkDerivation rec {
        inherit name;
        srcs = with builtins; map fetchurl pacmanSources;
        phases = [ "unpackPhase" "installPhase" ];
        nativeBuildInputs = [ pkgs.gnutar pkgs.zstd ];
        unpackPhase = builtins.concatStringsSep "\n" (builtins.map
          (src: ''
            ${pkgs.gnutar}/bin/tar -xvpf ${src} --exclude .PKGINFO --exclude .INSTALL --exclude .MTREE --exclude .BUILDINFO
          '') srcs);
        installPhase = ''
          mkdir -p $out
          cp -r -t $out *
        '';
      };
      crossConfig = {target, cairo, CGO_CPPFLAGS, CGO_LDFLAGS, GOOS, GOARCH}: let
        zigScriptsInst = zigScripts target;
      in {
        targetPkgs.cairo = cairo;
        config = {
          CGO_ENABLED = true;
          inherit CGO_CPPFLAGS CGO_LDFLAGS;
          preBuild = ''
            export ZIG_LOCAL_CACHE_DIR=$(${pkgs.coreutils}/bin/mktemp -d)
            export ZIG_GLOBAL_CACHE_DIR=$ZIG_LOCAL_CACHE_DIR
            export CC="${zigScriptsInst}/bin/zcc"
            export CXX="${zigScriptsInst}/bin/zxx"
            export GOOS=${GOOS}
            export GOARCH=${GOARCH}
          '';
        };
      };
    in {
      win64 = crossConfig rec {
        target = "x86_64-windows-gnu";
        cairo = fromPacman "cairo" [{
          url = "https://mirror.msys2.org/mingw/clang64/mingw-w64-clang-x86_64-cairo-1.17.4-4-any.pkg.tar.zst";
          sha256 = "1pxiz0kg24r8jfh2wiqdcj4g79xrbcv2qp7jsx0c2kjq1xwfknb0";
        }];
        CGO_CPPFLAGS = "-I${cairo}/clang64/include/cairo -I${cairo}/clang64/include";
        CGO_LDFLAGS = "-L${cairo}/clang64/lib -lcairo";
        GOOS = "windows";
        GOARCH = "amd64";
      };
      raspberryPi4 = crossConfig rec {
        target = "arm-linux-gnueabihf";
        cairo = fromDebs "cairo" [
          { url = "http://archive.raspberrypi.org/debian/pool/main/c/cairo/libcairo2-dev_1.16.0-5+rpt1_armhf.deb";
            sha256 = "1w7vh7j664pfz4jr3v52j6wg24f3ir9hfr9j1xcpxmm8pqyj0zkv"; }
          { url = "http://archive.raspberrypi.org/debian/pool/main/c/cairo/libcairo2_1.16.0-5+rpt1_armhf.deb";
            sha256 = "0wy5l77nmgyl8465bl864hjhkijlx7ipy4n9xikhnsbzcq95y61q"; }
        ];
        CGO_CPPFLAGS = "-I${cairo}/usr/include/cairo";
        CGO_LDFLAGS = "-L${cairo}/usr/lib/arm-linux-gnueabihf -lcairo";
        GOOS = "linux";
        GOARCH = "arm";
      };
    };
    buildApp = { system, vendorSha256, plugins ? [], targetPkgs ? nixpkgs.legacyPackages.${system}, config ? {} }:
      let
        pkgs = nixpkgs.legacyPackages.${system};
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
      in pkgs.buildGoModule (rec {
        name = "image-server";
        src = builtins.trace "sources at ${sources}" sources;
        modRoot = "src";
        subPackages = [ "." ];
        inherit vendorSha256;
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ targetPkgs.cairo ];
        preBuild = ''
          export PATH=$PATH:${pkgs.lib.makeBinPath nativeBuildInputs}
        '';
        overrideModAttrs = if targetPkgs == pkgs then null else _: {
          postBuild = ''
            patch -p0 <${./cairo.go.patch}
            patch -p0 <${./png.go.patch}
          '';
        };
      } // config);
    crossBuildRPi4App = config: (buildApp (config // (platforms config.system).raspberryPi4));
    crossBuildWin64App = config: (buildApp (config // (platforms config.system).win64));
  in (flake-utils.lib.eachDefaultSystem (system: rec {
    packages = {
      app = buildApp {
        inherit system;
        vendorSha256 = "sha256-yII94225qx8EAMizoPA9BSRP9lz0JL/UoPDNYROcvNw=";
      };
      rpi4app = crossBuildRPi4App {
        inherit system;
        vendorSha256 = "sha256-LjIii/FL42ZVpxs57ndVc5zFw7oK8mIqd+1o9MMcXx4=";
      };
      win64app = crossBuildWin64App {
        inherit system;
        vendorSha256 = "sha256-LjIii/FL42ZVpxs57ndVc5zFw7oK8mIqd+1o9MMcXx4=";
      };
    };
    defaultPackage = packages.app;
  })) // {
    lib = {
      inherit buildApp crossBuildRPi4App crossBuildWin64App;
      pluginMetadata = goModFile: {
        goModName = with builtins; head
          (match "module ([^[:space:]]+).*" (readFile goModFile));
      };
    };
  };
}