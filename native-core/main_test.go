package main

import "testing"

func TestCoreVersionIsPinned(t *testing.T) {
	if coreVersion != "nlash-core/0.2.0 mihomo/v1.19.30" {
		t.Fatalf("unexpected core version: %s", coreVersion)
	}
}
