#ifndef NLASH_CORE_NAPI_H
#define NLASH_CORE_NAPI_H

#include "napi/native_api.h"

namespace nlash {

// 耗时操作返回 Promise 并使用 N-API 工作线程，状态读取保持同步。
napi_value ValidateConfigAsync(napi_env env, napi_callback_info info);
napi_value StartCoreAsync(napi_env env, napi_callback_info info);
napi_value EnableCoreProxyAsync(napi_env env, napi_callback_info info);
napi_value DisableCoreProxyAsync(napi_env env, napi_callback_info info);
napi_value CoreProxyEnabledValue(napi_env env, napi_callback_info info);
napi_value StopCoreAsync(napi_env env, napi_callback_info info);
napi_value CoreStateValue(napi_env env, napi_callback_info info);
// 进程内只保留一个原生监听器，ArkTS CoreClient 负责向多个订阅者分发。
napi_value SetCoreEventListener(napi_env env, napi_callback_info info);
napi_value ClearCoreEventListener(napi_env env, napi_callback_info info);
napi_value ExecuteCoreCommandAsync(napi_env env, napi_callback_info info);

} // namespace nlash

#endif // NLASH_CORE_NAPI_H
