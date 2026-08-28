//go:build cgo

package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef void (*NlashCoreEventCallback)(int32_t event_type, int32_t state, int32_t code,
                                      const char* message, void* user_data);

static inline void NlashInvokeCoreEventCallback(NlashCoreEventCallback callback,
                                                int32_t event_type,
                                                int32_t state,
                                                int32_t code,
                                                const char* message,
                                                void* user_data) {
    callback(event_type, state, code, message, user_data);
}
*/
import "C"

import "unsafe"

//export NlashCoreVersion
func NlashCoreVersion() *C.char {
	return C.CString(coreVersion)
}

//export NlashCoreEcho
func NlashCoreEcho(value *C.char) *C.char {
	if value == nil {
		return C.CString("")
	}
	return C.CString(C.GoString(value))
}

//export NlashCoreValidateConfig
func NlashCoreValidateConfig(configPath *C.char) C.int32_t {
	if configPath == nil {
		return C.int32_t(coreInvalidArgument)
	}
	return C.int32_t(runtimeInstance.validate(C.GoString(configPath)))
}

//export NlashCoreStart
func NlashCoreStart(
	configPath *C.char,
	workDir *C.char,
	tunFD C.int32_t,
	mtu C.int32_t,
	protectSocketPath *C.char,
	generation *C.char,
) C.int32_t {
	if configPath == nil || workDir == nil || protectSocketPath == nil || generation == nil {
		return C.int32_t(coreInvalidArgument)
	}
	options := coreStartOptions{
		configPath:        C.GoString(configPath),
		workDir:           C.GoString(workDir),
		tunFD:             int(tunFD),
		mtu:               int(mtu),
		protectSocketPath: C.GoString(protectSocketPath),
		generation:        C.GoString(generation),
	}
	return C.int32_t(runtimeInstance.start(options))
}

//export NlashCoreStop
func NlashCoreStop() C.int32_t {
	return C.int32_t(runtimeInstance.stop())
}

//export NlashCoreState
func NlashCoreState() C.int32_t {
	return C.int32_t(runtimeInstance.getState())
}

//export NlashCoreLastError
func NlashCoreLastError() *C.char {
	return C.CString(runtimeInstance.getLastError())
}

//export NlashCoreExecuteCommand
func NlashCoreExecuteCommand(command *C.char) *C.char {
	if command == nil {
		return C.CString(marshalCommandResponse(commandFailure("INVALID_ARGUMENT", "command is missing")))
	}
	return C.CString(runtimeInstance.executeCommand(C.GoString(command)))
}

//export NlashCoreRegisterEventCallback
func NlashCoreRegisterEventCallback(callback C.NlashCoreEventCallback, userData unsafe.Pointer) {
	if callback == nil {
		setCoreEventHandler(nil)
		return
	}
	setCoreEventHandler(func(eventType coreEventType, state coreRuntimeState, code coreErrorCode, message string) {
		value := C.CString(message)
		defer C.free(unsafe.Pointer(value))
		C.NlashInvokeCoreEventCallback(
			callback,
			C.int32_t(eventType),
			C.int32_t(state),
			C.int32_t(code),
			value,
			userData,
		)
	})
}

//export NlashCoreUnregisterEventCallback
func NlashCoreUnregisterEventCallback() {
	setCoreEventHandler(nil)
}

//export NlashCoreFree
func NlashCoreFree(value *C.char) {
	C.free(unsafe.Pointer(value))
}

func main() {}
