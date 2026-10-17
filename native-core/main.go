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

/*
C ABI 返回的字符串均由 C.CString 分配，调用方须使用 NlashCoreFree 释放。
事件回调的 message 仅在回调期间有效，接收方需要异步使用时必须先复制。
*/

// NlashCoreVersion 返回固定的 Core 版本，供宿主检查原生库是否可用。
//
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

// NlashCoreStart 启动 Core；接管系统流量还需调用 NlashCoreEnableProxy。
//
//export NlashCoreStart
func NlashCoreStart(
	configPath *C.char,
	workDir *C.char,
) C.int32_t {
	if configPath == nil || workDir == nil {
		return C.int32_t(coreInvalidArgument)
	}
	options := coreStartOptions{
		configPath: C.GoString(configPath),
		workDir:    C.GoString(workDir),
	}
	return C.int32_t(runtimeInstance.start(options))
}

// NlashCoreEnableProxy 接收桥接层复制的 TUN FD，成功后由 Core 的 TUN 生命周期管理。
//
//export NlashCoreEnableProxy
func NlashCoreEnableProxy(
	tunFD C.int32_t,
	mtu C.int32_t,
	protectSocketPath *C.char,
	generation *C.char,
) C.int32_t {
	if protectSocketPath == nil || generation == nil {
		return C.int32_t(coreInvalidArgument)
	}
	options := coreProxyOptions{
		tunFD:             int(tunFD),
		mtu:               int(mtu),
		protectSocketPath: C.GoString(protectSocketPath),
		generation:        C.GoString(generation),
	}
	return C.int32_t(runtimeInstance.enableProxy(options))
}

//export NlashCoreDisableProxy
func NlashCoreDisableProxy() C.int32_t {
	return C.int32_t(runtimeInstance.disableProxy())
}

//export NlashCoreProxyEnabled
func NlashCoreProxyEnabled() C.int32_t {
	if runtimeInstance.isProxyEnabled() {
		return 1
	}
	return 0
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

// NlashCoreExecuteCommand 使用 JSON 信封传递业务命令，避免为每个操作扩展 C ABI。
//
//export NlashCoreExecuteCommand
func NlashCoreExecuteCommand(command *C.char) *C.char {
	if command == nil {
		return C.CString(marshalCommandResponse(commandFailure("INVALID_ARGUMENT", "command is missing")))
	}
	return C.CString(runtimeInstance.executeCommand(C.GoString(command)))
}

// NlashCoreRegisterEventCallback 替换进程内回调；调用可能来自 Go 的不同 goroutine。
//
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
