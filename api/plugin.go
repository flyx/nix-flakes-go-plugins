package api

import "github.com/ungerik/go-cairo"

// Plugin is the interface of mainapp plugins.
type Plugin interface {
	Paint(surface *cairo.Surface) error
}