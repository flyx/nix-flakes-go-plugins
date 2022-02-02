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
In order for our Flake-based plugin management to be viable as a general solution, it must also be able to target Nix-less environments.
Therefore, we will now explore how to compile our application for deployment in a Nix-less environment.

The most critical target platform is Windows, since it is not supported by Nix as host system.
Our goal will be to produce a native Windows binary.
Since it [is possible][1] to run NixOS on WSL, Windows folks will be able to build the application on Windows for Windows, with the fine print of doing it via cross-compilation on WSL.

A second target platform we will discuss is the Raspberry Pi 4.
While this is not wholly unsupported by Nix, the support is beta-grade at best.
Also, the Pi is simply not a very fast machine, so we might want to cross-compile for it even if we could compile natively simply to achieve faster build times.

The third target platform will be [OCI][2].
Like it or not, containers are widely employed and Go is a common language for writing web services that are deployed via container.
Therefore, we will explore how to build a container image with Nix.

## Setup, Again

We will use the same Go code we used for part 2.
Simply copy the whole directory `image-server` to `image-server-cross` to get started.
The new directory is to set the updated code apart in this article's repository.

We will rewrite the `flake.nix` completely, and I will show its new content bit by bit to discuss what we're doing.
You can fetch the file's complete content from [the repository][3].

## Cross Compiling

Nix [has support][4] for cross-compilation.
This would provide us with a cross-compiling GCC that could compile our code and all its dependencies.
However, Go is able to cross-compile by itself!
The main reason we'd want to use Nix' cross-compiling capabilities is because we do have some C dependencies we must cross-compile.
However, this would mean that we would need to build a cross-compiling GCC *and* cross-compile the *cairo* library since there are no binary caches for that.
That reeks of unnecessary complexity (and is also experimental: I wasn't able to get it to work on aarch64-darwin).

Thankfully, there is an alternative:
[Zig][5].
Zig is a language with a compiler that happens to bundle enough of clang and llvm that it can basically cross-compile C almost everywhere.
And using Zig to cross-compile Go has [already been explored][6].
So this is what we'll be doing.

Without further ado, let's start writing `image-server-cross/flake.nix`:

{% capture flake_src %}
{% include_relative image-server-cross/flake.nix %}
{% endcapture %}

{% assign flake = flake_src | newline_to_br | split: "<br />" %}

{% highlight nix %}
{{ flake | slice: 0, 12 | join: ""}}
{% endhighlight %}

We include Zig from a Flake instead of from `nixpkgs` to have the latest `0.9.0` version.
We also include Go 1.18, which has not yet been released but is available as beta version.
Go 1.18 fixes an [vital issue](https://github.com/golang/go/issues/43886) with cross-compiling for Windows.

**Beta software is not for production use, especially not compilers!**
I will update this article with the proper Go 1.18 version once it is out.
I created the `go-1.18` overlay primarily for this article.
The first Flake build will take some time since it needs to build Go 1.18 (it is not available in the binary cache).

{% highlight nix %}
{{ flake | slice: 12, 29 | join: ""}}
{% endhighlight %}

`go118pkgs` is a function that, given a `system`, instantiates nixpkgs with the given system and our Go 1.18 overlay.

`platforms` is a function that, given a `system`, shall give us a set of configurations for all target platforms we want to cross-compile to.

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
{{ flake | slice: 41, 27 | join: ""}}
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

{% highlight nix %}
{{ flake | slice: 68, 28 | join: "" }}
{% endhighlight %}

`platformConfig` defines the general framework shared by our target platforms.
What we do here is:

 * supply the four variables `CGO_CPPFLAGS`, `CGO_LDFLAGS`, `GOOS` and `GOARCH`, which will be directly handed over to the Go compiler.
   Since `buildGoModule` overrides `GOOS` and `GOARCH`, we set those directly in `preBuild`.
 * setup `CC` and `CXX` to contain our fancy Zig wrapper scripts.
   Again, those will be overridden somewhere because they are fairly central parameters for building, thus we set them in `preBuild`.
 * Zig uses cache directories. We must set these because else we will get errors because derivations are, obviously, not allowed to use cache directories in `$HOME`.
 * `CGO_ENABLED` is necessary because by default, cgo is disabled when cross-compiling.
 * patch the reference to `pkg-config` out of the `go-cairo` sources.
   This requires two patch files, so let's create them now.

`image-server-cross/cairo.go.patch`:

{% highlight patch %}
{% include_relative image-server-cross/cairo.go.patch %}
{% endhighlight %}

`image-server-cross/png.go.patch`

{% highlight patch %}
{% include_relative image-server-cross/png.go.patch %}
{% endhighlight %}

Nothing spectacular here, we simply remove the lines instructing cgo to call *pkg-config*.

Back to our `flake.nix`.
We are now ready to define our first target platform:

{% highlight nix %}
{{ flake | slice: 96, 22 | join: "" }}
{% endhighlight %}

This is the platform for the Raspberry Pi 4.
Since the packages there are debian-based, *cairo* is split into a main package and a dev package, which we need both to be able to link against it.
Therefore, we fetch both packages with our helper function, which creates our `cairo` derivation from those two inputs.
Notice how our library files in this case are inside `lib/arm-linux-gnueabihf` so we need to set up `CGO_LDFLAGS` accordingly.

{% highlight nix %}
{{ flake | slice: 118, 22 | join: "" }}
{% endhighlight %}

This is our platform for Windows.
We see that Zig likes to call the CPU architecture `x86_64` while Go calls it `amd64`, but those are just different names for the same thing.
Windows, unlike Raspberry Pi OS, is not typically managed with a package manager.
Therefore, we'll fetch *all* required libraries so we can package them along our binary for easy installation – this includes the *cairo* library and all libraries it depends on.
To facilitate this, we add a `postInstall` script that copies all DLL files to the executable's location.
To unclutter our `flake.nix`, I listed the required libraries in a separate file `win64-deps.txt`;

{% highlight plain %}
{% include_relative image-server-cross/win64-deps.txt %}
{% endhighlight %}

I wrote this file by navigating [the webinterface](https://packages.msys2.org/package/mingw-w64-clang-x86_64-cairo?repo=clang64) like a barbarian and collecting the dependencies.
There is probably a nicer way but I don't know pacman well enough to figure it out.
In any case, if you ever need to do this, use

{% highlight plain %}
nix-hash --type sha256 --to-base32 <hash>
{% endhighlight %}

to convert the hashes given by the package repository to what you want to have in your `flake.nix`.
This concludes our `platforms` setup.

## Building the Application

We're back in our `flake.nix`!
Compared to our previous setup, our new `buildApp` gains two parameters, `targetPkgs` and `buildGoModuleOverrides`:

{% highlight nix %}
{{ flake | slice: 140, 14 | join: "" }}
{% endhighlight %}

`targetPkgs` is the list of packages for the target system, which can potentially contain foreign packages.
But, if not specified explicitly, it will just be the same as our host system's packages.
`buildGoModuleOverrides` is the additional configuration for cross-compiling, which is supplied by our platform definitions.

What follows is the setup of `sources`, which has not changed at all:

{% highlight nix %}
{{ flake | slice: 154, 27 | join: "" }}
{% endhighlight %}

And finally, our call to `buildGoModule`:

{% highlight nix %}
{{ flake | slice: 181, 14 | join: "" }}
{% endhighlight %}

The main change is that we refer now to `targetPkgs.cairo`, which is the foreign library we fetched before for our target platforms.

{% highlight nix %}
{{ flake | slice: 195, 4 | join: "" }}
{% endhighlight %}

Not only do we want to be able to cross-compile in the main application's Flake, we obviously also want plugin Flakes to be able to do it.
Therefore, we define these two functions that cross-build our application for the respective targets, which take the same parameters as `buildApp`.

## The Flake's Packages

Let's have our Flake provide the native main application, along with packages for Windows and the Raspberry Pi:

{% highlight nix %}
{{ flake | slice: 199, 17 | join: "" }}{{ flake | slice: 225, 12 | join: "" }}
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
People on Linux can run this via `wine`, or so I'm told:

{% highlight bash %}
nix run nixpkgs#wine.wineWowPackages.stable -- result/bin/windows_amd64/image-server.exe
{% endhighlight %}

However, this is not supported on macOS.
You can of course test it on an actual Windows installation if you have one.

Let's try the Raspberry Pi build:

{% highlight bash %}
nix build .#rpi4app
{% endhighlight %}

Aaand that fails at the time of writing – we're hitting a [known Zig issue][10].
Zig is, after all, pre-1.0 software, so let's not blame it.
We did get pretty far though!
Hopefully this issue will be resolved in the future so that we can actually cross-compile to the Raspberry Pi.

## OCI Image

The last thing we'll do is to create an OCI container image.
For this, we'll simply add another package to our `image-server` (behind the `win64app`):

{% highlight bash %}
{{ flake | slice: 216, 9 | join: ""}}
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

This is a gzipped tarball which can be loaded for example into Docker via

{% highlight plan %}
gunzip -c result | docker load
{% endhighlight %}

I won't go into details about how to run Docker images since that documented in detail elsewhere.

Mind that usable Docker images must contain Linux binaries.
On macOS, you'd need to cross-compile with Nix' actual cross-compiling system so that Nix can gather the set of all dependencies, which is not something I will explore here.
You could instead use a NixOS VM or build image.

You can of course provide a function that builds a customized image from a list of plugins; try that as an exercise.

## Conclusion

With this article, I set out to show that Nix Flakes can be a viable alternative to Go's `-buildmode=plugin`.
In my opinion, it was largely a success in that I managed to be able to target even Windows.
The main drawbacks are that I used beta software (Go 1.18 and Zig) to achieve that goal.
These seem to be minor though, as Go 1.18 proper is set to be released in March 2022, and while Zig as a language has not reached a major version yet, we only use its bundled `clang` compiler which *is* production-ready.
The error we ran into when trying to build for the Raspberry Pi is just missing header files for glibc, which hopefully will be fixed in a future release.

## Final Words

The topics explored in this article are quite complex.
It is likely that there are flaws in it.
If you have suggestions how to improve the article, you can use the GitHub repository's [issue tracker][11].

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
 [11]: https://github.com/flyx/nix-flakes-go-plugins/issues