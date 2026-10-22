package main

import (
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	coreDNS "github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/tunnel/statistic"
	D "github.com/miekg/dns"
)

const maxDNSHistory = 200

type dnsQueryRecord struct {
	ID        string   `json:"id"`
	Host      string   `json:"host"`
	Type      string   `json:"type"`
	Answers   []string `json:"answers"`
	Initiator string   `json:"initiator"`
	Upstream  string   `json:"upstream"`
	Cached    bool     `json:"cached"`
	Start     int64    `json:"start"`
	Duration  int64    `json:"duration"`
	Error     string   `json:"error"`
}

// 查询仅保留在内存环形缓冲区，不写入磁盘或日志。
type dnsQueryHistory struct {
	mu      sync.Mutex
	records [maxDNSHistory]dnsQueryRecord
	next    uint64
	count   int
	since   time.Time
	enabled bool
}

var dnsHistory dnsQueryHistory

func init() {
	coreDNS.DefaultQueryNotify = dnsHistory.append
}

func (history *dnsQueryHistory) append(query coreDNS.QueryRecord) {
	history.mu.Lock()
	defer history.mu.Unlock()
	if !history.enabled || query.Start.Before(history.since) {
		return
	}
	record := dnsQueryRecord{
		Host: strings.TrimSuffix(query.Question.Name, "."), Type: D.TypeToString[query.Question.Qtype],
		Answers: []string{}, Initiator: query.Initiator, Upstream: query.Upstream,
		Cached: query.Cached, Start: query.Start.UnixMilli(), Duration: max(0, time.Since(query.Start).Milliseconds()),
	}
	if query.Cached {
		record.Duration = 0
	}
	if record.Type == "" {
		record.Type = fmt.Sprintf("TYPE%d", query.Question.Qtype)
	}
	if query.Err != nil {
		record.Error = "解析失败，请检查上游 DNS 与网络"
	} else if query.Msg != nil {
		if query.Msg.Rcode != D.RcodeSuccess {
			record.Error = D.RcodeToString[query.Msg.Rcode]
		}
		answerBytes := 0
		for _, answer := range query.Msg.Answer {
			var value string
			switch answer := answer.(type) {
			case *D.A:
				value = answer.A.String()
			case *D.AAAA:
				value = answer.AAAA.String()
			case *D.CNAME:
				value = strings.TrimSuffix(answer.Target, ".")
			default:
				value = answer.String()
			}
			if len(value) > 512 {
				value = value[:512]
			}
			answerBytes += len(value)
			if answerBytes > 1024 {
				break
			}
			record.Answers = append(record.Answers, value)
			if len(record.Answers) == 16 {
				break
			}
		}
	}
	if len(record.Upstream) > 512 {
		record.Upstream = record.Upstream[:512]
	}
	record.ID = fmt.Sprint(history.next)
	history.records[history.next%maxDNSHistory] = record
	history.next++
	history.count = min(history.count+1, maxDNSHistory)
}

func (history *dnsQueryHistory) snapshot() []dnsQueryRecord {
	history.mu.Lock()
	defer history.mu.Unlock()
	result := make([]dnsQueryRecord, 0, history.count)
	for i := 0; i < history.count; i++ {
		record := history.records[(history.next-1-uint64(i))%maxDNSHistory]
		record.Answers = append([]string{}, record.Answers...)
		result = append(result, record)
	}
	sort.SliceStable(result, func(i, j int) bool { return result[i].Start > result[j].Start })
	return result
}

func (history *dnsQueryHistory) setEnabled(enabled bool) {
	history.mu.Lock()
	defer history.mu.Unlock()
	history.records = [maxDNSHistory]dnsQueryRecord{}
	history.count = 0
	history.since = time.Now()
	history.enabled = enabled
}

func clearProxyActivity() {
	dnsHistory.setEnabled(false)
	closeAllConnections()
	statistic.DefaultManager.ResetStatistic()
}
