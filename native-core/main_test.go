package main

import "testing"

func TestCoreVersionIsPinned(t *testing.T) {
	if coreVersion != "nlash-core/0.2.0 Clash.Meta/8380d0e7462f" {
		t.Fatalf("unexpected core version: %s", coreVersion)
	}
}
