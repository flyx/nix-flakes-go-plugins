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

## Raspberry Pi

