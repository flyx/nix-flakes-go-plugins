package count

import (
	"example.com/api"
	"github.com/ungerik/go-cairo"
	"log"
	"strconv"
)

type CountPlugin struct {
	count int
}

func (cp *CountPlugin) Paint(surface *cairo.Surface) error {
	cp.count += 1
	surface.SetFontSize(24.0)
	surface.MoveTo(200.0, 20.0)
	surface.ShowText(strconv.Itoa(cp.count))
	return nil
}

func Plugin() api.Plugin {
	log.Println("initializing count-plugin")
	return &CountPlugin{count: 0}
}