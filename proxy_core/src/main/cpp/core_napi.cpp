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

struct NativeEvent {
    int32_t type;
    int32_t state;
    int32_t code;
    std::string message;
};

std::mutex eventMutex;
napi_threadsafe_function eventFunction = nullptr;

void SetIntProperty(napi_env env, napi_value object, const char *name, int32_t value)
{
    napi_value property = nullptr;
    napi_create_int32(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

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
    event.release();
}

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
    STOP,
    COMMAND,
};

struct AsyncContext {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    AsyncOperation operation = AsyncOperation::VALIDATE;
    std::string configPath;
    CoreStartOptions startOptions;
    CoreResult result {CoreErrorCode::INTERNAL_ERROR, "core operation did not run"};
    std::string command;
    std::string commandResult;
};

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
        case AsyncOperation::STOP:
            context->result = StopCore();
            break;
        case AsyncOperation::COMMAND:
            context->commandResult = ExecuteCoreCommand(context->command);
            break;
    }
}

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
        ReadNamedInt32(env, args[0], "tunFd", context->startOptions.tunFd);
        ReadNamedInt32(env, args[0], "mtu", context->startOptions.mtu);
        ReadNamedString(env, args[0], "protectSocketPath", context->startOptions.protectSocketPath);
        ReadNamedString(env, args[0], "generation", context->startOptions.generation);
    }
    return QueueAsync(env, std::move(context), "nlashStartCore");
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
