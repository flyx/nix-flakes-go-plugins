package main

import (
	"log"
	"net/http"
	
	"example.com/api"
	"github.com/ungerik/go-cairo"
)

var plugins []api.Plugin

func main() {
	log.Println("serving at http://localhost:8080")
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		surface := cairo.NewSurface(cairo.FORMAT_ARGB32, 240, 80)
		surface.SelectFontFace(
			"serif", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
		surface.SetFontSize(32.0)
		surface.SetSourceRGB(0.0, 0.0, 1.0)
		surface.MoveTo(10.0, 50.0)
		surface.ShowText("Hello World")
		for _, p := range plugins {
			if err := p.Paint(surface); err != nil {
				panic(err)
			}
		}
		png, _ := surface.WriteToPNGStream()
		w.Write(png)
		surface.Finish()
	})
	
	log.Fatal(http.ListenAndServe(":8080", nil))
}