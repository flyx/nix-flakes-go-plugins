---
layout: default
title: "Exploring Nix Flakes: Usable Go Plugins"
part: 2
parttitle: APIs and Dependencies
kind: article
permalink: /nix-flakes-go/part2/
weight: 7
---

In the previous part we created a plugin with an `init` function so that it runs some code when compiled into the `mainapp`.
Of course, that does give the plugin no practical possibility to interact with the mainapp.
To do this, we'll need a plugin API that defines how the main application and the plugins communicate.

To be able to define an API, we need to give our application some functionality.
For this article, the functionality will be that it creates an image and serves it via HTTP; plugins can add to the image before it is served.
This functionality is chosen for two reasons:

 * By serving via HTTP, the application can easily be run from an OCI image, which we will do in part 3.
 * We create an image via [cairo][1], so that we have a dependency to a C library.
   This will enable us in part 3 to discuss handling C dependencies during cross-compilation.

The API we need cannot be part of our mainapp's Go module since that would create a circular dependency (remember that our mainapp imports the plugin's package).
Thus, we will create a separate directory `api` inside our root.
Inside that directory, create a Go module:

{% highlight bash %}
nix run nixpkgs#go mod init example.com/api
nix run nixpkgs#go -- get -d github.com/ungerik/go-cairo
{% endhighlight %}

We'll give the API a `Plugin` type that defines the entry point of our plugin.
Create a file `api/plugin.go` with the following content:

{% highlight go %}
{% include_relative api/plugin.go %}
{% endhighlight %}

In an actual application, you'd probably publish the API and thus could reference it directly in `go.mod` with its module path.
But to keep it local – and also because we don't have control over *example.com* – we'll make this a Nix Flake just like everything else (remember how I said in part 1 that we could manage standard dependencies with Nix Flakes? That's what we'll be doing with the API).

Create a file `api/flake.nix`:

{% highlight nix %}
{% include_relative api/flake.nix %}
{% endhighlight %}

This gives us a flake whose `defaultPackage` is simply the API module's sources.

Now we need the main application that implements our functionality.
To set it apart from our earlier iteration, create a directory `image-server` in the root directory.
In it, create another module:

{% highlight bash %}
nix run nixpkgs#go mod init example.com/image-server
nix run nixpkgs#go -- get -d github.com/ungerik/go-cairo
{% endhighlight %}

Now let's write our application.
Put this in `image-server/main.go` (this is a modified version of the [go-cairo example][2], extended with an HTTP server and plugin interaction).

{% highlight go %}
{% include_relative image-server/main.go %}
{% endhighlight %}

The `plugins` variable is to hold our plugins, however we didn't write code to populate it yet.
We do this in an updated `plugins.go`, for which we'll need a template `image-server/plugins.go.nix` again:

{% highlight nix %}
{% include_relative image-server/plugins.go.nix %}
{% endhighlight %}

Compared to our previous iteration, we now give the imported plugin packages actual names.
These are not the packages' original names, but `p1`, `p2` etc., so that we'll never have name collisions.

The code assumes that the root package of any plugin provides a function `Plugin()` which returns an `api.Plugin`.
This is akin to the entry point of a classical C dynamic-library-plugin.

Now we need the flake of our new application at `image-server/flake.nix`:

{% highlight nix %}
{% include_relative image-server/flake.nix %}
{% endhighlight %}

Compared to our previous iteration, we integrated the API code and give `pkgs` to `plugins.go.nix`.
We also added `pkg-config`, made it available in the `PATH`, and added `cairo` as dependency.
*go-cairo* is configured to use `pkg-config` to discover how to link to `cairo`, which is why we need those dependencies.

As always, in `image-server`, check in everything and run:

{% highlight bash %}
git add . ../api
nix flake update
git add flake.lock
git commit -a -m "image server"
nix run
{% endhighlight %}

After we see our log line, visit `http://localhost:8080` in your browser to query the image we generate.
Stop the server with `^C`.
This sums up our updated main application.

## Count Plugin

*It's the plugin that counts!*

Our current implementation always creates the same image.
We will now write a plugin that adds to the image the number of times the image has been queried.
Create a directory `count-plugin` and do the usual initialization in it:

{% highlight bash %}
nix run nixpkgs#go mod init example.com/count-plugin
nix run nixpkgs#go -- get -d github.com/ungerik/go-cairo
{% endhighlight %}

Write the plugin's implementation into `count-plugin/plugin.go`:

{% highlight go %}
{% include_relative count-plugin/plugin.go %}
{% endhighlight %}

We provide a `func Plugin()` that is the plugin's entry point.
We define a type `CountPlugin` that implements `api.Plugin`.
That's it.

Now we need `count-plugin/flake.nix`, which is very similar to our previous plugin's Flake, apart from the inclusion of the API:

{% highlight nix %}
{% include_relative count-plugin/flake.nix %}
{% endhighlight %}

Mind that for this `go.mod` we only need the `require` directive – the `replace` in the main application's `go.mod` will be honored.
Let me stress again that we only refer to the API via flake to keep everything local and in actual code you most probably want to have a publicly available standard Go module as API.

Let's finalize the plugin and run it:

{% highlight bash %}
git add .
nix flake update
git add flake.lock
git commit -a -m "count plugin"
nix run
{% endhighlight %}

Now when you access `http://localhost:8080/` again, you will have a running number as part of the image, which increases when you reload.
Mind that browsers do background prefetching and caching, so you might not see every number.

## Multiple Plugins

At this point, we have seen that we can create plugin-based applications and write usable plugins for them.
What we haven't talked about is what to do when we want to have multiple plugins active – currently, a plugin Flake simply defines an application where exactly this plugin is active.
We did this mostly for convenience.

A tailored setup with a defined set of plugins would be written in an own Flake or as part of a system configuration.
It would use `buildApp` to build the application with all desired plugins.
Each plugin can be retrieved from its Flake via the `plugin` package.

 [1]: https://www.cairographics.org
 [2]: https://github.com/ungerik/go-cairo/blob/master/go-cairo-example/go-cairo-example.go