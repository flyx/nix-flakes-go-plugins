# Exploring Nix Flakes: Usable Go Plugins

This repository contains the sources for my article [Exploring Nix Flakes: Usable Go Plugins][1].

The directories `api`, `count-plugin`, `image-server`, `image-server-cross`, `mainapp` and `simple-plugin` contain the Go sources and Nix Flakes discussed in the article.
You can build & run those directly after cloning this repository.

The `index.md` and `part*.md` files contain the sources of the article itself.
They include the other source files for code listings.

If you want to contribute a PR, do `nix run` in the root directory to build the article and check that everything is in order (you can reach it at http://localhost:4000).
`part3.md` splits the `image-server-cross/flake.nix` file by line numbers, so if you change that Flake, you need to update the line numbers.

 [1]: https://flyx.org/nix-flakes-go/