#include "core_napi.h"

#include "core_bridge.h"

#ifdef NLASH_HAS_GO_CORE
#include "libnlash_core.h"
#endif

#include <memory>
#include <mutex>
#include <string>

namespace nlash {

namespace {

// 独立持有 message 副本，Go 回调返回后原始字符串即失效。
struct NativeEvent {
    int32_t type;
    int32_t state;
    int32_t code;
    std::string message;
};

// 同步回调投递与监听器替换，防止使用已释放的线程安全函数。
std::mutex eventMutex;
napi_threadsafe_function eventFunction = nullptr;

void SetIntProperty(napi_env env, napi_value object, const char *name, int32_t value)
{
    napi_value property = nullptr;
    napi_create_int32(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

// 在 JS 线程消费事件；环境销毁时也由 unique_ptr 回收排队中的数据。
void CallEventListener(napi_env env, napi_value callback, void *context, void *data)
{
    (void)context;
    std::unique_ptr<NativeEvent> event(static_cast<NativeEvent *>(data));
    if (env == nullptr || callback == nullptr) {
        return;
    }
    napi_value object = nullptr;
    napi_create_object(env, &object);
    SetIntProperty(env, object, "type", event->type);
    SetIntProperty(env, object, "state", event->state);
    SetIntProperty(env, object, "code", event->code);
    napi_value message = nullptr;
    napi_create_string_utf8(env, event->message.c_str(), event->message.size(), &message);
    napi_set_named_property(env, object, "message", message);

    napi_value receiver = nullptr;
    napi_get_undefined(env, &receiver);
    napi_call_function(env, receiver, callback, 1, &object, nullptr);
}

// Go 可从任意线程回调，只通过 threadsafe_function 投递，不能直接操作 JS 值。
void OnCoreEvent(int32_t type, int32_t state, int32_t code, const char *message, void *userData)
{
    (void)userData;
    auto event = std::make_unique<NativeEvent>();
    event->type = type;
    event->state = state;
    event->code = code;
    event->message = message == nullptr ? "" : message;

    std::lock_guard<std::mutex> lock(eventMutex);
    if (eventFunction == nullptr ||
        napi_call_threadsafe_function(eventFunction, event.get(), napi_tsfn_nonblocking) != napi_ok) {
        return;
    }
    // 投递成功后，事件的所有权转移给 CallEventListener。
    event.release();
}

// 调用方须持有 eventMutex；先断开 Go 事件源，再中止 JS 投递队列。
void ClearEventFunctionLocked()
{
#ifdef NLASH_HAS_GO_CORE
    NlashCoreUnregisterEventCallback();
#endif
    if (eventFunction != nullptr) {
        napi_release_threadsafe_function(eventFunction, napi_tsfn_abort);
        eventFunction = nullptr;
    }
}

enum class AsyncOperation {
    VALIDATE,
    START,
    ENABLE_PROXY,
    DISABLE_PROXY,
    STOP,
    COMMAND,
};

/*
 * 每次异步调用独立持有入参、结果和 Promise。
 * 工作线程只访问 C++ 数据，JS 值的创建与 Promise 完成统一放在完成回调中。
 */
struct AsyncContext {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    AsyncOperation operation = AsyncOperation::VALIDATE;
    std::string configPath;
    CoreStartOptions startOptions;
    CoreProxyOptions proxyOptions;
    CoreResult result {CoreErrorCode::INTERNAL_ERROR, "core operation did not run"};
    std::string command;
    std::string commandResult;
};

// 先查询 UTF-8 字节数，再额外预留结尾空字符，支持多字节配置路径。
bool ReadString(napi_env env, napi_value value, std::string &target)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    std::string buffer(length + 1, '\0');
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) {
        return false;
    }
    buffer.resize(length);
    target = buffer;
    return true;
}

bool ReadNamedString(napi_env env, napi_value object, const char *name, std::string &target)
{
    napi_value value = nullptr;
    return napi_get_named_property(env, object, name, &value) == napi_ok && ReadString(env, value, target);
}

bool ReadNamedInt32(napi_env env, napi_value object, const char *name, int32_t &target)
{
    napi_value value = nullptr;
    return napi_get_named_property(env, object, name, &value) == napi_ok &&
        napi_get_value_int32(env, value, &target) == napi_ok;
}

napi_value CreateResultValue(napi_env env, const CoreResult &result)
{
    napi_value object = nullptr;
    napi_create_object(env, &object);

    napi_value ok = nullptr;
    napi_get_boolean(env, result.IsOk(), &ok);
    napi_set_named_property(env, object, "ok", ok);

    napi_value code = nullptr;
    napi_create_int32(env, static_cast<int32_t>(result.code), &code);
    napi_set_named_property(env, object, "code", code);

    napi_value message = nullptr;
    napi_create_string_utf8(env, result.message.c_str(), result.message.size(), &message);
    napi_set_named_property(env, object, "message", message);
    return object;
}

void ExecuteAsync(napi_env env, void *data)
{
    (void)env;
    auto *context = static_cast<AsyncContext *>(data);
    switch (context->operation) {
        case AsyncOperation::VALIDATE:
            context->result = ValidateCoreConfig(context->configPath);
            break;
        case AsyncOperation::START:
            context->result = StartCore(context->startOptions);
            break;
        case AsyncOperation::ENABLE_PROXY:
            context->result = EnableCoreProxy(context->proxyOptions);
            break;
        case AsyncOperation::DISABLE_PROXY:
            context->result = DisableCoreProxy();
            break;
        case AsyncOperation::STOP:
            context->result = StopCore();
            break;
        case AsyncOperation::COMMAND:
            context->commandResult = ExecuteCoreCommand(context->command);
            break;
    }
}

// 业务失败也 resolve 结构化结果，由 ArkTS 根据 ok/code 决定是否抛出异常。
void CompleteAsync(napi_env env, napi_status status, void *data)
{
    std::unique_ptr<AsyncContext> context(static_cast<AsyncContext *>(data));
    if (status != napi_ok) {
        if (context->operation == AsyncOperation::COMMAND) {
            context->commandResult =
                R"({"ok":false,"code":"INTERNAL_ERROR","message":"native async work failed"})";
        } else {
            context->result = {CoreErrorCode::INTERNAL_ERROR, "native async work failed"};
        }
    }
    napi_value value = nullptr;
    if (context->operation == AsyncOperation::COMMAND) {
        napi_create_string_utf8(env, context->commandResult.c_str(), context->commandResult.size(), &value);
    } else {
        value = CreateResultValue(env, context->result);
    }
    napi_resolve_deferred(env, context->deferred, value);
    napi_delete_async_work(env, context->work);
}

// 入队成功由完成回调回收 context；创建或入队失败则在当前线程完成 Promise 并清理。
napi_value QueueAsync(napi_env env, std::unique_ptr<AsyncContext> context, const char *name)
{
    napi_value promise = nullptr;
    napi_create_promise(env, &context->deferred, &promise);
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &resourceName);
    AsyncContext *rawContext = context.release();
    if (napi_create_async_work(
            env, nullptr, resourceName, ExecuteAsync, CompleteAsync, rawContext, &rawContext->work) != napi_ok ||
        napi_queue_async_work(env, rawContext->work) != napi_ok) {
        rawContext->result = {CoreErrorCode::INTERNAL_ERROR, "failed to queue native async work"};
        napi_value result = nullptr;
        if (rawContext->operation == AsyncOperation::COMMAND) {
            constexpr const char *errorJson =
                R"({"ok":false,"code":"INTERNAL_ERROR","message":"failed to queue native async work"})";
            napi_create_string_utf8(env, errorJson, NAPI_AUTO_LENGTH, &result);
        } else {
            result = CreateResultValue(env, rawContext->result);
        }
        napi_resolve_deferred(env, rawContext->deferred, result);
        if (rawContext->work != nullptr) {
            napi_delete_async_work(env, rawContext->work);
        }
        delete rawContext;
    }
    return promise;
}

} // namespace

napi_value ValidateConfigAsync(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto context = std::make_unique<AsyncContext>();
    context->operation = AsyncOperation::VALIDATE;
    if (argc != 1 || !ReadString(env, args[0], context->configPath)) {
        context->configPath.clear();
    }
    return QueueAsync(env, std::move(context), "nlashValidateConfig");
}

napi_value StartCoreAsync(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto context = std::make_unique<AsyncContext>();
    context->operation = AsyncOperation::START;
    if (argc == 1) {
        ReadNamedString(env, args[0], "configPath", context->startOptions.configPath);
        ReadNamedString(env, args[0], "workDir", context->startOptions.workDir);
    }
    return QueueAsync(env, std::move(context), "nlashStartCore");
}

napi_value EnableCoreProxyAsync(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto context = std::make_unique<AsyncContext>();
    context->operation = AsyncOperation::ENABLE_PROXY;
    if (argc == 1) {
        ReadNamedInt32(env, args[0], "tunFd", context->proxyOptions.tunFd);
        ReadNamedInt32(env, args[0], "mtu", context->proxyOptions.mtu);
        ReadNamedString(env, args[0], "protectSocketPath", context->proxyOptions.protectSocketPath);
        ReadNamedString(env, args[0], "generation", context->proxyOptions.generation);
    }
    return QueueAsync(env, std::move(context), "nlashEnableCoreProxy");
}

napi_value DisableCoreProxyAsync(napi_env env, napi_callback_info info)
{
    (void)info;
    auto context = std::make_unique<AsyncContext>();
    context->operation = AsyncOperation::DISABLE_PROXY;
    return QueueAsync(env, std::move(context), "nlashDisableCoreProxy");
}

napi_value CoreProxyEnabledValue(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value value = nullptr;
    napi_get_boolean(env, IsCoreProxyEnabled(), &value);
    return value;
}

napi_value StopCoreAsync(napi_env env, napi_callback_info info)
{
    (void)info;
    auto context = std::make_unique<AsyncContext>();
    context->operation = AsyncOperation::STOP;
    return QueueAsync(env, std::move(context), "nlashStopCore");
}

napi_value ExecuteCoreCommandAsync(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto context = std::make_unique<AsyncContext>();
    context->operation = AsyncOperation::COMMAND;
    if (argc != 1 || !ReadString(env, args[0], context->command)) {
        context->command = "{}";
    }
    return QueueAsync(env, std::move(context), "nlashExecuteCoreCommand");
}

napi_value CoreStateValue(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value value = nullptr;
    napi_create_int32(env, static_cast<int32_t>(GetCoreState()), &value);
    return value;
}

napi_value SetCoreEventListener(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_valuetype type = napi_undefined;
    if (argc != 1 || napi_typeof(env, args[0], &type) != napi_ok || type != napi_function) {
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        return undefined;
    }

    std::lock_guard<std::mutex> lock(eventMutex);
    ClearEventFunctionLocked();
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "nlashCoreEvents", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_threadsafe_function(
            env, args[0], nullptr, resourceName, 0, 1, nullptr, nullptr, nullptr,
            CallEventListener, &eventFunction) == napi_ok) {
#ifdef NLASH_HAS_GO_CORE
        NlashCoreRegisterEventCallback(OnCoreEvent, nullptr);
#endif
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value ClearCoreEventListener(napi_env env, napi_callback_info info)
{
    (void)info;
    std::lock_guard<std::mutex> lock(eventMutex);
    ClearEventFunctionLocked();
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

} // namespace nlash
