---
layout: default
title: "Exploring Nix Flakes: Usable Go Plugins"
part: 3
parttitle: Targets and Deployment
kind: article
permalink: /nix-flakes-go/part3/
weight: 8
---

What we did until now assumed that the target system has Nix with Flake support available.
This will not always be the case.
In order for our Flake-based plugin management to be viable as a general solution, it must also be able to serve Nix-less environments.
Therefore, we will now explore how to compile our application for deployment in a Nix-less environment.

The most important target platform will be Windows, which is not supported by Nix as host system.
It [is possible][1] to run NixOS directly on WSL, though you can also run Nix in any other Linux distribution running under WSL.
This way, you can actually build your code on Windows for Windows, even though we will employ cross-compilation.

A second target platform we will discuss is the Raspberry Pi 4.
While this is not wholly unsupported by Nix, the support is beta-grade at best.
More importantly, the Pi is simply not a very fast machine, so we might want to cross-compile for it even if we could compile natively simply to achieve faster build times.

The third target platform will be [OCI][2].
Like it or not, containers are widely employed and Go is a common language for writing web services that are deployed via container.
Therefore, we will explore how to build a container image with Nix.

## Setup, Again

We we use the same Go code we used for part 2.
Simply copy the whole directory `image-server` to `image-server-cross` to get started.
The new directory is to set the updated code apart in the repository.

We will rewrite the `flake.nix` completely, and I will show its new content bit by bit to discuss what we're doing.
You can fetch the file's complete content from [the repository][3].

## Cross Compiling

Nix [has support][4] for cross-compilation.
This would provide us with a cross-compiling GCC that could compile our code and all its dependencies.
However, Go is able to cross-compile by itself!
The only reason we'd want to use Nix' cross-compiling capabilities is because we do have some C dependencies we must cross-compile.
However, this would mean that we would need to build a cross-compiling GCC *and* cross-compile the *cairo* library.
That reeks of unnecessary complexity (and is also experimental: I wasn't able to get it to work on aarch64-darwin).

Thankfully, there is an alternative:
[Zig][5].
Zig is a language with a compiler that happens to bundle enough of clang and llvm that it can basically cross-compile C almost everywhere.
And using Zig to cross-compile Go has [already been explored][6].
So this is what we'll be doing.

So without further ado, let's start writing `image-server-cross/flake.nix`:

{% assign flake = include_relative image-server-cross/flake.nix | split "\n" %}

{% highlight nix %}
{{ flake | slice 0, 35 | join "\n"}}
{% endhighlight %}

We include Zig from a Flake instead of from `nixpkgs` to have the latest `0.9.0` version.
In our outputs, we define a function `platforms` which, given a `system`, shall give us a set of configurations for all target platforms we want to cross-compile to.

`zigScripts` creates a derivation that contains the scripts `zcc` and `zxx` which are wrappers that call zig's bundled, cross-compiling clang (as described in [the article][6] mentioned above).
This derivation depends on the `target` parameter, which is a [Target Triplet][7] that tells Zig about our target system.

This concludes our Zig setup.

## C Dependencies

I already said that I don't want to cross-compile all C dependencies.
So what should we do instead?
If our target was supported by nixpkgs, we could theoretically pull our dependencies from the binary cache; however this won't work for Windows.
However, the dependencies *are* packaged for our target systems – just not with Nix.

Our course of action is therefore to just pull the dependencies from their native package repositories, which will be good enough for linking against them.
For Windows, the package repository we'll use is [MSYS2][8], which uses *pacman*.
For the Raspberry Pi, it will be [the repository of Raspberry Pi OS][9] (no fancy web UI available apparently), which is mostly just debian, and thus uses *dpkg*.

Let's write functions for those two package managers that we can use to pull packages from their repositories:

{% highlight nix %}
{{ flake | slice 36, 61 | join "\n"}}
{% endhighlight %}

Each function takes a `name`, that will be the name of the generated derivation, and a list of sources, which are inputs to `fetchurl`.
The derivations fetch their sources, unpack them, and write the result to their store path.
Pretty straightforward as long as you can figure out those `tar` parameters.

## Configuring Go

The last bit we need for our cross-compilation is the configuration for the Go compiler.
This is a bit tricky:
Go modules that wrap C files tend to use *pkg-config* to query their C compilation and link flags.
*go-cairo* is a module that does this.
The foreign packages we will fetch do come with *pkg-config* descriptions, but they assume a normal installation of the package into `/`, which we do not do.
The path of least resistance for us is thus to disable retrieval of parameters via *pkg-config* and instead just supply the C flags manually.

Disabling *pkg-config* is something we will do with patches later.
What we'll be doing now is to define a function that creates a set of attributes for `buildGoModule` that enables cross-compilation, and fill it with the appropriate parameters for our two target systems:

{% highlight nix %}
{{ flake | slice 62, 104 | join "\n" }}
{% endhighlight %}

Okay so what happens here?
`crossConfig` defines the general framework shared by both target platforms.
What we do here is:

 * supply the four variables `CGO_CPPFLAGS`, `CGO_LDFLAGS`, `GOOS` and `GOARCH`, which will be directly handed over to the Go compiler.
   Since `buildGoModule` overrides `GOOS` and `GOARCH`, we set those directly in `preBuild`.
 * setup `CC` and `CXX` to contain our fancy Zig wrapper scripts.
   Again, those will be overridden somewhere because they are fairly central parameters for building, thus we set them in `preBuild`.
 * Zig uses cache directories. We must set these because else we will get errors because derivations are, obviously, not allowed to use cache directories in `$HOME`.
 * `CGO_ENABLED` is necessary because by default, cgo is disable when cross-compiling.

Then, `win64` is our first platform.
We see that Zig likes to call the CPU architecture `x86_64` while Go calls it `amd64`, but those are just different names for the same thing.
We fetch the *cairo* package from MSYS2 and use it to provide `targetPkgs.cairo`.
By inspecting the directory layout inside that package, we know where the include files and libraries are located within those packages and set up `CGO_CPPFLAGS` and `CGO_LDFLAGS` accordingly.

The second platform is `raspberryPi4`.
Since our packages here are debian-based, *cairo* are split into a main package and a dev package.
We fetch both packages and create our `cairo` derivation from it.
Notice how our library files in this case are inside `lib/arm-linux-gnueabihf` so we need to set up `CGO_LDFLAGS` accordingly.

## Building the Application

Our `buildApp` gains two new parameters, `targetPkgs` and `config`:

{% highlight nix %}
{{ flake | slice 105, 105 | join "\n" }}
{% endhighlight %}

`targetPkgs` is the list of packages for the target system, which can potentially contain foreign packages.
But, if not specified explicitly, it will just be the same as our host system's packages.
`config` is the additional configuration for cross-compiling, which we have defined above.

What follows is the setup of `sources`, which has not changed at all:

{% highlight nix %}
{{ flake | slice 106, 141 | join "\n" }}
{% endhighlight %}

And finally, our call to `buildGoModule`:

{% highlight nix %}
{{ flake | slice 142, 159 | join "\n" }}
{% endhighlight %}

The main change is that we refer now to `targetPkgs.cairo`.
Also new is the attribute `overrideModAttrs` which modifies the generation of our vendored Go modules.
Remember how we wanted to disable *pkg-config* in *go-cairo*?
This is where we do it – but only if we're cross-compiling, i.e. when `targetPkgs` is not the same as `pkgs`.

Create the two patches we apply in their respective files:
`image-server-cross/cairo.go.patch`:

{% highlight patch %}
{% include_relative image-server-cross/cairo.go.patch %}
{% endhighlight %}

`image-server-cross/png.go.patch`

{% highlight patch %}
{% include_relative image-server-cross/png.go.patch %}
{% endhighlight %}

Nothing spectacular here, we simply remove the lines instructing cgo to call *pkg-config*.
Back to our `image-server-cross/flake.nix`:

{% highlight nix %}
{{ flake | slice 160, 161 | join "\n" }}
{% endhighlight %}

Not only do we want to be able to cross-compile in the main application's Flake, we obviously also want plugin Flakes to be able to do it.
Therefore, we define two functions that cross-build our application for the respective targets, which take the same parameters as `buildApp`.

## The Flake's Packages

Let's have our Flake provide the native main application, along with packages for Windows and the Raspberry Pi:

{% highlight nix %}
{{ flake | slice 162, 175 | join "\n" }}
{{ flake | slice 184, 196 | join "\n" }}
{% endhighlight %}

As discussed, we now also provide our two cross-compiling functions in the public `lib`.

## Build it!

Phew, that was a long journey.
First, let's finalize everything and check that the native app still works:

{% highlight bash %}
git add .
nix flake update
git add flake.lock
git commit -a -m "cross compiling app"
nix run
{% endhighlight %}

This works.
If you want, fetch some images, then kill it.

Now for the interesting part:
Let's compile for Windows!

{% highlight bash %}
nix build .#win64app
{% endhighlight %}

This should give us a nice `result`.
People on Linux can run this via `wine`:

{% highlight bash %}
nix run nixpkgs#wine.wineWowPackages.stable -- result/bin/windows_amd64/image-server.exe
{% endhighlight %}

However, this is not supported on macOS.
You can of course test it on an actual Windows installation if you have one.

Finally, let's try the Raspberry Pi build:

{% highlight bash %}
nix build .#rpi4app
{% endhighlight %}

Aaand that fails at the time of writing – we're hitting a [known Zig issue][10].
Zig is, after all, pre-1.0 software, so let's not blame it.
We did get pretty far though!
Hopefully this issue will be resolved in the future so that we can actually cross-compile to the Raspberry Pi.

## OCI Image

The last thing we'll do is to create an OCI container.
For this, we'll simply add another package to our `image-server` (behind the `win64app`):

{% highlight bash %}
{{ flake | slice 176, 183 | join "\n"}}
{% endhighlight %}

Commit and run:

{% highlight bash %}
git commit -a -m "container image"
nix build .#container-image
readlink result
{% endhighlight %}

This should give you something like

{% highlight plain %}
/nix/store/wn3af4ivdk9xbwrr64ays2ygxbr00c8j-docker-image-image-server-oci.tar.gz
{% endhighlight %}

This is a gzipped tarball which can be loaded for example into Docker via `gunzip -c result | docker load`.

Mind that usable Docker images must contain Linux binaries.
On macOS, you'd need to cross-compile with Nix' actual cross-compiling system so that Nix can gather the set of all dependencies, which is not something I will explore here.
You could instead use a NixOS VM or build image.

You can of course provide a function that builds a customized image from a list of plugins; try that as an exercise.

## Final Words

If you have suggestions how to improve this article, you can use the GitHub repository's issue tracker.



 [1]: https://github.com/Trundle/NixOS-WSL
 [2]: https://opencontainers.org
 [3]: https://github.com/flyx/nix-flakes-go-plugins/blob/master/image-server-cross/flake.nix
 [4]: https://nixos.wiki/wiki/Cross_Compiling
 [5]: https://ziglang.org/
 [6]: https://dev.to/kristoff/zig-makes-go-cross-compilation-just-work-29ho
 [7]: https://wiki.osdev.org/Target_Triplet
 [8]: https://packages.msys2.org/
 [9]: http://archive.raspberrypi.org/debian/pool/main/
 [10]: https://github.com/ziglang/zig/issues/3287