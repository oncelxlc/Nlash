//go:build !cgo

package main

// main keeps host-side tests buildable when CGO is disabled. The OHOS
// c-shared artifact is always built with CGO enabled and uses main.go.
func main() {}
