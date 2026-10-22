package main

import (
	"io"

	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/sirupsen/logrus"
)

// 清除旧版本写入的 DNS 映射，保留节点选择与订阅缓存。
func clearPersistedDNS(cache *cachefile.CacheFile) error {
	if cache.DB == nil {
		return nil
	}
	if err := cache.FakeIpStore().FlushFakeIP(); err != nil {
		return err
	}
	return cache.FakeIpStore6().FlushFakeIP()
}

func init() {
	// Mihomo's default logger writes detailed connection data to stdout. Nlash only
	// exposes the stable, sanitized events emitted by events.go.
	logrus.SetOutput(io.Discard)
}
