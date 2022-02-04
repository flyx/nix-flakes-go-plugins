---
layout: default
title: "Exploring Nix Flakes: Usable Go Plugins"
part: 1
parttitle: Setup for Plugin Consumption
kind: article
permalink: /nix-flakes-go/part1/
weight: 6
---

In this part we will write a main application which can consume plugins.
We will then write a plugin and explore how to inject this plugin into the main application.
Our general approach is as follows:

 * The main application is a Nix Flake.
 * Plugins are Nix Flakes.
 * The final application is a Nix derivation.
   The main application's flake will provide a function which builds that derivation.
   The function will take a list of plugins as input.
 * The final application will have the Go code of both the main application and any plugins compiled into a single executable.

Now, you are perhaps thinking

> If we need to compile the whole application with a known list of plugins, those are not really plugins, but build flags.

and that is not entirely wrong.
But we do preserve most features of runtime-injected plugins, including:

 * We can fetch plugins from external sources.
 * The original application does not need to know the plugins we're injecting.

What we actually lose is the possibility to combine readily compiled binaries, i.e. someone who wants to setup the application with their hand-chosen set of plugins must use Nix to compile their executable.

This might seem like a drawback of our approach.
However, we are simply using Nix as a build system.
While Go libraries tend to not use any build system other than the Go compiler itself, an application will likely need one anyway, for example to bundle resources or build container images.
We are thus simply choosing Nix instead of some other build system (like e.g. a Makefile, a Dockerfile or whatever else you can imagine).

An actual drawback is that Nix does not support all platforms Go supports, most prominently Windows.
To remedy this, I will show in part 3 how to release for Windows from a Nix-capable host.

## Setting up the Main Application

Create a directory `mainapp`.
This will contain our main application.
We'll be using Go modules, so do this in `mainapp`:

{% highlight bash %}
nix run nixpkgs#go mod init "example.com/mainapp"
{% endhighlight %}

This will give us a `go.mod` file.
We use `example.com` as domain because by convention, any Go module path starts with a domain.
The domain won't be used for querying anything.
Now, let's write a simple main application in `mainapp/main.go`:

{% highlight go %}
{% include_relative mainapp/main.go %}
{% endhighlight %}

To finish the main application, we provide it with a `mainapp/flake.nix`:

{% highlight nix %}
{% include_relative mainapp/flake.nix %}
{% endhighlight %}

First, we build a derivation *sources* which will contain all sources we want to compile.
We use `nix-filter` to explicitly exclude the `flake.nix` which is something sensible to do.
If we don't exclude `flake.nix`, any change there would trigger a rebuild even if it was unnecessary.
`nix-filter` doesn't work on `self` so you need to give `./.`.

We build the sources as explicit derivation instead of doing our modifications during the phases of `buildGoModule` because building a Go module consumes the sources two times:
First it vendors all Go dependencies, then it compiles the sources while injecting the vendored dependencies.
We want our changes to endure through both steps, so we build an explicit derivation containing our sources.

In our `sources`, we append lines to our `go.mod` file to reference any given plugins (we require that a plugin is a Go module).
For a plugin named `example.com/my-plugin`, we'd append the following lines:

{% highlight plain %}
require example.com/my-plugin v0.0.0
replace example.com/my-plugin => ./vendor-nix/example.com/my-plugin
{% endhighlight %}

The `require` directive adds our plugin module as dependency; the version number is arbitrary.
The `replace` directive tells Go that instead of searching for the plugin module in the module cache, it shall be searched at the given path.
We can't give a nix store path to `replace` because that path propagates to `vendor/modules.txt`, a file created during vendoring.
That file is part of the `go-modules` derivation created by `buildGoModule`, which is a fixed output derivation and as such is not allowed to depend on other derivations, which is why having a store path there would lead to an error.
Consequentially, we'll have to setup a directory `vendor-nix` in our sources, and copy our plugins' sources there, which we do in the `buildPhase`.

What we're doing here is quite similar to what vendoring does and in fact, we could use this approach to manage all our Go module dependencies via Nix.
However that would seriously harm tooling because if our dependencies are not in `go.mod` during development, an editor would be unable to give context-aware suggestions when referencing entities from that module in our code.
This is not a problem with plugins because the non-generated code of our main application is not aware of any plugin module.

Speaking of generated code, we see that we add a file `plugins.go`.
This is because a reference to our plugin modules in `go.mod` alone does not cause them to be compiled into the main application.
In `plugins.go`, we will reference each given plugin in Go code, so that the plugin's code is actually compiled into the executable.
To not overcrowd the `flake.nix`, we put the template for `plugins.go` in an own file, `mainapp/plugins.go.nix`:

{% highlight nix %}
{% include_relative mainapp/plugins.go.nix %}
{% endhighlight %}

The comment line has a standard format recognized by Go that tells the compiler the file is autogenerated.
That is useful for tooling that, for example, checks code style, which should not be done on autogenerated files.
For each plugin, we write an import line

{%highlight go %}
_ "<module path>"
{% endhighlight %}

The underscore means that it's okay for the imported package to not be referenced (we would get a compiler error otherwise).
The `init` function generated will be called after the `init` functions of all plugins referenced due to package initialization order.

With our plugins in `vendor-nix`, our additional dependencies in `go.mod` and our plugin loading happening in `plugins.go`, we have collected everything needed for our `sources` derivation.
We install everything into `$out/src`.

Now we can use `buildGoModule`, give our sources as input, and build our plugins.
`subPackages` tells `buildGoModule` which is the main module we want to compile, and the path given is interpreted relative to our `modRoot`.
As you can see, we use `vendorSha256`, which is an additional input besides the plugin list to the `buildApp` function we declare.
This is the hash over all vendored sources *include the plugin sources*.
Since it depends on the plugins we use, it must be supplied by the caller.
To know the hash you need to use, just give `nixpkgs.lib.fakeSha256` initially and build once.
Then, update the value to be the one that was expected as given in the error message.

In the bottom part of the Flake, we use `buildApp` to define a default package of our flake, that is:
Our application without any plugins.
Additionally, we export `buildApp` and a function `pluginMetadata`.
That function takes the path to a `go.mod` file as input and crudely extracts the module's name from it.
It will not work for every variation of the syntax that is allowed, but works for canonical files generated via `go mod init`, which is good enough.
We'll need this in our plugins, since in our sources, we assumed a plugin supplies us with `goPlugin.goModName`.
This is, by the way, how we recognize a derivation being a plugin: It contains a `goPlugin` attribute.
For an actual application, you'd want to change that name since you'll want to ensure that it is a plugin for *your* application.

And that's how we integrate plugins into our build!
Now, in `mainapp`, create the `flake.lock`, check in everything, and run it:

{% highlight bash %}
git add . # required for nix flake update
nix flake update
git add flake.lock
git commit -a -m "initial commit"
nix run
{% endhighlight %}

(Committing is optional, but saves us from a warning that the repository is dirty.)
This should give us:

{% highlight plain %}
2022/01/06 22:58:31 plugins have been initialized.
Hello, world!
{% endhighlight %}

# Writing the First Plugin

Create another directory `simple-plugin`.
This will contain our first plugin.
Again, do

{% highlight bash %}
nix run nixpkgs#go mod init
{% endhighlight %}

in the directory.

Let's write another minimal Go file `simple-plugin/simple.go`:

{% highlight go %}
{% include_relative simple-plugin/simple.go %}
{% endhighlight %}

Now to make this directory a plugin, we write the file `simple-plugin/flake.nix`:

{% highlight nix %}
{% include_relative simple-plugin/flake.nix %}
{% endhighlight %}

For `vendorSha256` just supply `nixpkgs.lib.fakeSha256` initially and then build once, as discussed above.
Then, update the value to be the one that was expected as given in the error message.

To satisfy the assertions of the main application about plugins, we set `goPlugin` via `passthru` and use the function we defined earlier to read the plugin's module path.
Sure, we could just copy it from `go.mod`, but I prefer having a single source of truth.
Then, we make the `plugin` derivation provide the plugin's sources in `src` within its nix store directory.

Besides `plugin`, we provide a package `app` that is our main application extended by our plugin.
Let us build this now!
Just like before, in `simple-plugin`, create the `flake.lock`, check in everything, and run it:

{% highlight bash %}
git add .
nix flake update
git add flake.lock
git commit -a -m "first plugin"
nix run
{% endhighlight %}

The output should look similar to this:

{% highlight plain %}
2022/01/04 00:10:02 initializing simple-plugin
2022/01/04 00:10:02 plugins have been initialized.
Hello, world!
{% endhighlight %}

We see that the plugin code is loaded.
However it cannot do much yet – this will be the topic of the next part.