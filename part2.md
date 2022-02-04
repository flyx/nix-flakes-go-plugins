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

 * By serving via HTTP, the application can easily be delivered as an OCI image, which we will do in part 3.
 * We create an image via [cairo][1], so that we have a dependency to a C library.
   This will enable us in part 3 to discuss handling C dependencies during cross-compilation.

The API we need cannot be part of our mainapp's Go module since that would create a circular dependency (remember that our mainapp imports the plugin's module).
Thus, we will create a separate directory `api` inside our root.
Inside that directory, create a Go module and setup the `go-cairo` dependency:

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

This gives us a flake whose `src` output is simply the API module's sources (this is a non-standard output but that's fine for our local setup).

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

The `plugins` variable is to hold our plugins.
To populate it, we'll extend the code we generate into `plugins.go`.
Create a new template `image-server/plugins.go.nix` to do this:

{% highlight nix %}
{% include_relative image-server/plugins.go.nix %}
{% endhighlight %}

Compared to our previous iteration, we now give the imported plugin packages actual names.
The generated code will look like this:

{% highlight go %}
import (
	"log"
	p1 "<plugin 1 path>"
	p2 "<plugin 2 path>"
)

func init() {
	plugins = append(plugins, p1.Plugin())
	plugins = append(plugins, p2.Plugin())
}
{% endhighlight %}

We generate package names `p1`, `p2` etc to avoid any possibility for name collisions.
The code assumes that the root package of any plugin provides a function `Plugin()` which returns an `api.Plugin`.
This is akin to the entry point of a classical C dynamic-library-plugin.

Now we need the flake of our new application at `image-server/flake.nix`:

{% highlight nix %}
{% include_relative image-server/flake.nix %}
{% endhighlight %}

Compared to our previous iteration, we integrated the API code and give `nixpkgs.lib` to `plugins.go.nix`.
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
In `Paint`, we add a running number to the image.
That's it.

Now we need `count-plugin/flake.nix`, which is very similar to our previous plugin's Flake, apart from the inclusion of the API:

{% highlight nix %}
{% include_relative count-plugin/flake.nix %}
{% endhighlight %}

For this `go.mod` we only need the `require` directive – the `replace` in the main application's `go.mod` will be honored.
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
Browsers do background prefetching and caching, so you might not see every number.

## Multiple Plugins

At this point, we have seen that we can create plugin-based applications and write usable plugins for them.
What we haven't talked about is what to do when we want to have multiple plugins active – currently, a plugin Flake simply defines an application where exactly this plugin is active.
We did this mostly for convenience.

A tailored setup with a defined set of plugins would be written in an own Flake or as part of a system configuration, like this:

{% highlight nix %}
let
  refPlugin = url: {
    inherit url;
    nixpkgs.follows = "nixpkgs";
    utils.follows = "utils";
    image-server.follows = "image-server";
  };
in {
  description = "Tailored image-server";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    utils.url = github:numtide/flake-utils;
    image-server = {
      url = path:../image-server;
      nixpkgs.follows = "nixpkgs";
      utils.follows = "utils";
    };
    first = refPlugin path:../first-plugin;
    second = refPlugin path:../second-plugin;
  };
  outputs = {self, nixpkgs, utils, image-server, first, second}:
    utils.lib.eachDefaultSystem (system: {
      defaultPackage = image-server.lib.buildApp {
        inherit system;
        vendorSha256 = nixpkgs.lib.fakeSha256;
        plugins = [ first.packages.${system}.plugin
                    second.packages.${system}.plugin ];
      };
    });
}
{% endhighlight %}

Is it necessary to have platform-dependent packages for our plugins if they merely contain sources?
For what we did here it isn't, but it might be the case for other applications.
The alternative would be to put them into some non-standard Flake output.

We now have explored how to make our main application and our plugins communicate via an API.
We have also seen how to incorporate C dependencies with Nix.
What remains now is to be able to target systems that don't support Nix, most importantly Windows.
This is what we'll be doing in the next and final part.

 [1]: https://www.cairographics.org
 [2]: https://github.com/ungerik/go-cairo/blob/master/go-cairo-example/go-cairo-example.go