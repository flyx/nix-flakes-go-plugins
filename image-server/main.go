package main

import (
	"example.com/api"
	"github.com/ungerik/go-cairo"
	"io/ioutil"
	"log"
	"net/http"
	"os"
)

var plugins []api.Plugin

func toPNG(surface *cairo.Surface) []byte {
	tmpFile, err := ioutil.TempFile("", "")
	if err != nil {
		panic(err)
	}
	tmpFileName := tmpFile.Name()
	defer os.Remove(tmpFileName)
	_ = tmpFile.Close()
	_ = surface.WriteToPNG(tmpFileName)
	ret, err := ioutil.ReadFile(tmpFileName)
	if err != nil {
		panic(err)
	}
	return ret
}

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		surface := cairo.NewSurface(cairo.FORMAT_ARGB32, 240, 80)
		surface.SelectFontFace("serif", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
		surface.SetFontSize(32.0)
		surface.SetSourceRGB(0.0, 0.0, 1.0)
		surface.MoveTo(10.0, 50.0)
		surface.ShowText("Hello World")
		for _, p := range plugins {
			if err := p.Paint(surface); err != nil {
				panic(err)
			}
		}
		w.Write(toPNG(surface))
		surface.Finish()
	})
	
	log.Fatal(http.ListenAndServe(":8080", nil))
}