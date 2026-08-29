package main

import "sync"

const maxCoreProgressBytes = 8 * 1024

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

func emitCoreProgressEvent(state coreRuntimeState, message string) {
	if len(message) == 0 || len(message) > maxCoreProgressBytes {
		return
	}
	dispatchCoreEvent(coreEventProxyDelayProgress, state, coreOK, message)
}

func dispatchCoreEvent(eventType coreEventType, state coreRuntimeState, code coreErrorCode, message string) {
	coreEvents.RLock()
	handler := coreEvents.handler
	coreEvents.RUnlock()
	if handler != nil {
		handler(eventType, state, code, message)
	}
}
