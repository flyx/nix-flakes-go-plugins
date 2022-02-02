---
layout: default
title: "Exploring Nix Flakes: Usable Go Plugins"
part: 1
parttitle: Setup for Plugin Consumption
kind: article
permalink: /nix-flakes-go/part1/
weight: 6
---

The general approach is as follows:

 * The main application is a Nix Flake.
 * Plugins are Nix Flakes.
 * The final application is a Nix derivation built by a generator supplied by the main flake, called on a list of plugins. It compiles the main application's and all plugins' code to a single executable file.

Now, you are perhaps thinking

> If we need to compile the whole application with a known list of plugins, those are not really plugins, but build flags.

and that is not entirely wrong.
But we do preserve most features of runtime-injected plugins, including:

 * We can fetch plugins from external sources.
 * The original application does not need to know the plugins we're injecting.

What we actually lose is the possibility to combine readily compiled binaries, i.e. someone who wants to setup the application with their hand-chosen set of plugins must use Nix to compile their executable.
Scenarios where this is impossible seem to be exotic, at least with Go projects (yes I will show later that we can build Windows binaries even though Nix doesn't support Windows as host).

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

Let's have an overview of what's going on here:

 * We use `nix-filter` to explicitly exclude the `flake.nix` which is something sensible to do.
   If we don't exclude `flake.nix`, any change there would trigger a rebuild even if it was unnecessary.
   Mind that `nix-filter` doesn't work on `self` so you need to give `./.`.
 * The `buildApp` function takes the target `system`, along with a list of plugins, as input, and builds our application.
   It additionally needs a `vendorSha256`, which is the hash over all external Go modules.
   Since that hash changes if we include plugins, the value must be provided as argument.
 * You may wonder how to know the `vendorSha256` value, and the one I give here may be wrong depending on your nixpkgs' Go version.
   To know the hash you need to use, just give `nixpkgs.lib.fakeSha256` initially and build once.
   Then, update the value to be the one that was expected as given in the error message.
 * The `pluginMetadata` is function we'll use in plugins.
   It takes the path to a `go.mod` file as input and crudely extracts the module's name from it.
   It will not work for every variation of the syntax that is allowed, but works for canonical files generated via `go mod init`, which is good enough.
 * In `buildApp`, we see that plugins are to provide a set `goPlugin` which is to contain the plugin's module name.
   We establish that a derivation is a consumable plugin if it has a `goPlugin` attribute.
   In an actual application, we'd use a more specialized name to ensure it is a plugin for *our* application.

Using the intermediate `sources` derivation accomplishes multiple things:

 * The reason we create a separate derivation instead of e.g. use `postConfigure` is that `buildGoModule` uses the sources two times:
   Once for vendoring all external module references, and once for building the code.
   The `go.mod` we modify is used for both, so instead of configuring it two times, we just create a derivation having that modification and use it as source.
 * The second reason we create a separate derivation is that we need to copy the plugin's sources into the main sources.
   This happens at the beginning of `buildPhase`, where we use the dedicated `vendor-nix` directory to copy the plugins' sources into.
   We will later redirect requests for those sources to that directory via `replace` directives we create in our `go.mod`.
   
   Mind that we *cannot* redirect Go directly to a plugin's nix store directory with a `replace` directive.
   Doing that would propagate the store path of the plugin into `vendor/modules.txt`, a file created during vendoring.
   That file is part of the `go-modules` derivation created by `buildGoModule`, which is a fixed output derivation and as such is not allowed to depend on other derivations.
   If we followed that path, Nix would complain with `error: path <…> is not valid`, because the fixed output derivation contains a store path and thus depends on other derivations, which is forbidden.
 * The application needs to know about the plugins, so we need to append plugin references to `go.mod` via `require` directives.
   Then, we create `replace` directives as discussed above so that Go finds the plugins's sources inside `vendor-nix`.
   
   Note that this approach could also be used to manage standard Go dependencies via Nix Flakes, instead of listing them in the source tree's `go.mod`.
   Keep in mind that modifying `go.mod` during build is fine, but if we do it inside `nix develop`, it will modify the original, checked-in file.
   I haven't found a good solution yet to avoid accidentally doing this, other than not having a `go.mod` in the source tree which would harm tooling during development.
 * Referencing the plugin in `go.mod` does not suffice, the Go code also needs to reference a package from the plugin.
   Therefore we generate a file `plugin.go` from the list of plugins that does that.

To not overcrowd the `flake.nix`, we put the template for `plugins.go` in an own file, `mainapp/plugins.go.nix`:

{% highlight nix %}
{% include_relative mainapp/plugins.go.nix %}
{% endhighlight %}

The comment line has a standard format recognized by Go that tells the compiler the file is autogenerated.
That is useful for tooling that, for example, checks code style, which should not be done on autogenerated files.
For each plugin, we write an import line `_ "<module path>"`.
The underscore means that it's okay for the imported package to not be referenced (we would get a compiler error otherwise).
The `init` function generated will be called after the `init` functions of all plugins referenced due to package initialization order.

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