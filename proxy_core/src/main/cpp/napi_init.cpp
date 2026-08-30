#include "napi/native_api.h"

#include "core_bridge.h"
#include "core_napi.h"

namespace {

napi_value CoreVersion(napi_env env, napi_callback_info info)
{
    (void)info;
    const std::string version = nlash::CoreVersion();
    napi_value returnValue = nullptr;
    napi_create_string_utf8(env, version.c_str(), version.size(), &returnValue);
    return returnValue;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"coreVersion", nullptr, CoreVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"validateConfig", nullptr, nlash::ValidateConfigAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startCore", nullptr, nlash::StartCoreAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"enableCoreProxy", nullptr, nlash::EnableCoreProxyAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"disableCoreProxy", nullptr, nlash::DisableCoreProxyAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"coreProxyEnabled", nullptr, nlash::CoreProxyEnabledValue, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopCore", nullptr, nlash::StopCoreAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"coreState", nullptr, nlash::CoreStateValue, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setCoreEventListener", nullptr, nlash::SetCoreEventListener, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"clearCoreEventListener", nullptr, nlash::ClearCoreEventListener, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"executeCoreCommand", nullptr, nlash::ExecuteCoreCommandAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}
EXTERN_C_END

static napi_module proxyCoreModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "proxy_core",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

} // namespace

extern "C" __attribute__((constructor)) void RegisterProxyCoreModule(void)
{
    napi_module_register(&proxyCoreModule);
}
