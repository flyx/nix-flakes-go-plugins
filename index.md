---
layout: default
title: "Exploring Nix Flakes: Usable Go Plugins"
title_short: Nix Flakes and Go
kind: article
permalink: /nix-flakes-go/
weight: 5
date: 2022-02-04
updated: 2022-02-17
has_parts: true
---

Building plugin-supporting applications in [Go](https://go.dev/) is currently a sub-par experience.
Go does have a `-buildmode=plugin` that lets you create `.so` files, which can then be loaded as plugin in a Go application. But:

 * It [doesn't work on Windows][1].
 * It [doesn't work well with vendoring][2].
 * Since [shared libraries are deprecated][3], every plugin is huge because they can't share even the standard library with the main application.

In this article, I will show how to use [Nix Flakes][4] as a build system for Go supporting plugin management.
This article has three parts, excluding the abstract you are just reading:

 * **[Part 1: Setup for Plugin Consumption](part1/)**
 
   I will show how to set up your application as Nix Flake that can be extended with plugins, and I will show how to write a first plugin as proof-of-concept.
   This part is the one most focused on Nix Flakes.
 
 * **[Part 2: APIs and Dependencies](part2/)**
 
   I will show how to give your application a plugin API and how to consume it from within a plugin.
   I will also show how to depend on external C libraries.
 
 * **[Part 3: Targets and Releases](part3/)**
 
   I will show how to build a Windows binary from a Nix-capable host (e.g. NixOS on WSL).
   I will also show how to build an [OCI][5] image that is consumable for example by [podman][6] or [Docker][7].
   
   Independently from plugins, this part may also be of interest to people who simply want to cross-compile Go applications with C dependencies.

I will assume you are familiar with Nix Flakes and Go.
In particular, I will show some complex Nix expressions and assume you can read them.
If you don't know much about Nix and are in a hurry, I recommend [*this article*](https://serokell.io/blog/practical-nix-flakes) for a quick overview of the language and Flakes.
A proper way to learn about Nix is the [*Nix Pills*](https://nixos.org/guides/nix-pills/) series, and [*this series*](https://www.tweag.io/blog/2020-05-25-flakes/) about Nix Flakes.

This article may also be interesting for people who simply are curious how to use Nix with Go.
To follow the instructions in this article, you need the `nix` utility installed and Flake support enabled.
Executing the commands shown in this article will potentially trigger downloads of multiple GB of data.
 
If you want to follow the article's instructions, create an empty directory that will be the root for all files and subdirectories we'll create
We need all files processed by Nix to be checked in to version control, so initialize a git repository in this directory with `git init`.
All code discussed in this article is available [on GitHub][8], so if you don't want to copy code from the article, you can also just clone that repository.

## Changelog

### 2022-02-17

 * +Working RPi 4 build and .deb package creation.

 [1]: https://github.com/golang/go/issues/19282
 [2]: https://github.com/golang/go/issues/20481
 [3]: https://github.com/golang/go/issues/47788
 [4]: https://nixos.wiki/wiki/Flakes
 [5]: https://opencontainers.org
 [6]: https://podman.io
 [7]: https://www.docker.com
 [8]: https://github.com/flyx/nix-flakes-go-plugins