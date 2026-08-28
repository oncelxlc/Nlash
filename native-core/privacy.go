package main

import (
	"io"

	"github.com/sirupsen/logrus"
)

func init() {
	// Mihomo's default logger writes detailed connection data to stdout. Nlash only
	// exposes the stable, sanitized events emitted by events.go.
	logrus.SetOutput(io.Discard)
}
