{
  inputs = {
    nix-filter.url = github:numtide/nix-filter;
  };
  outputs = {self, nix-filter}: {
    src = nix-filter.lib.filter {
      root = ./.;
      exclude = [ ./flake.nix ./flake.lock ];
    };
  };
}