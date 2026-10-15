# Third-Party Notices

## Go runtime

The `libnlash_core.so` library embeds the Go 1.27.0 runtime. Its BSD-style license is reproduced in `licenses/go-LICENSE`. The ARM64 General Dynamic TLS backport is pinned to Go Gerrit change commit `97ce7c6ef39edf2a0a0eba7d6fd1075abf26dc2f` and remains covered by the same Go license.

## Clash.Meta (Mihomo)

The `libnlash_core.so` library embeds the [chen08209/Clash.Meta fork of Mihomo](https://github.com/chen08209/Clash.Meta), pinned to commit `8380d0e7462f061a964323e9bf3129a236fcc5d5` by module source, pseudo-version and Go module checksum in `VERSION`. Clash.Meta is licensed under GPL-3.0; its license text is reproduced in `licenses/mihomo-GPL-3.0`.

This artifact is restricted to internal device validation. Complete transitive-license review and all GPL distribution obligations must be completed before any external distribution.
