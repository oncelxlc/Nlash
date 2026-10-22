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
	// Detailed logs stay in the opt-in memory buffer; never send them to system stdout.
	logrus.SetOutput(io.Discard)
}
