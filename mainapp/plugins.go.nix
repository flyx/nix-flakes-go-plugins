plugins: ''
package main

// Code generated by Nix. DO NOT EDIT.

import (
	"log"
	${builtins.foldl'
	    (a: b: a + "\n\t_ \"${b.goPlugin.goModName}\"")
	    "" plugins}
)

func init() {
	log.Println("plugins have been initialized.")
} 
''