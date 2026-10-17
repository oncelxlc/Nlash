package main

import "sync"

const maxCoreProgressBytes = 8 * 1024

// coreEventType 的数值须与 ArkTS CoreClient 的事件映射顺序一致。
type coreEventType int32

const (
	coreEventLifecycle coreEventType = iota
	coreEventLog
	coreEventUnexpectedExit
	coreEventProtectFailure
	coreEventProxyDelayProgress
)

type coreEventHandler func(eventType coreEventType, state coreRuntimeState, code coreErrorCode, message string)

var coreEvents = struct {
	sync.RWMutex
	handler coreEventHandler
}{}

func setCoreEventHandler(handler coreEventHandler) {
	coreEvents.Lock()
	defer coreEvents.Unlock()
	coreEvents.handler = handler
}

func emitCoreEvent(eventType coreEventType, state coreRuntimeState, code coreErrorCode, message string) {
	dispatchCoreEvent(eventType, state, code, sanitizeCoreErrorText(message))
}

// emitCoreProgressEvent 保留进度 JSON 的完整结构；普通日志的截断规则不适用于此处。
func emitCoreProgressEvent(state coreRuntimeState, message string) {
	if len(message) == 0 || len(message) > maxCoreProgressBytes {
		return
	}
	dispatchCoreEvent(coreEventProxyDelayProgress, state, coreOK, message)
}

// dispatchCoreEvent 在释放注册锁后调用回调，避免回调重入注册逻辑时死锁。
func dispatchCoreEvent(eventType coreEventType, state coreRuntimeState, code coreErrorCode, message string) {
	coreEvents.RLock()
	handler := coreEvents.handler
	coreEvents.RUnlock()
	if handler != nil {
		handler(eventType, state, code, message)
	}
}
