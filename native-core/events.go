package main

import "sync"

type coreEventType int32

const (
	coreEventLifecycle coreEventType = iota
	coreEventLog
	coreEventUnexpectedExit
	coreEventProtectFailure
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
	coreEvents.RLock()
	handler := coreEvents.handler
	coreEvents.RUnlock()
	if handler != nil {
		handler(eventType, state, code, sanitizeCoreErrorText(message))
	}
}
