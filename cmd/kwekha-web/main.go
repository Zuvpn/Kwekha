
package main

import (
	"log"
	"net/http"
)

func main() {
	log.Println("Kwekha WebPanel starting...")

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("OK"))
	})

	log.Println("Listening on :3300")
	log.Fatal(http.ListenAndServe(":3300", nil))
}
