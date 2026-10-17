#include "core_bridge.h"

#include <unistd.h>

#ifdef NLASH_HAS_GO_CORE
#include "libnlash_core.h"
#endif

namespace nlash {

namespace {

// 复制错误文本后立即归还 C ABI 内存，避免将跨语言指针暴露到异步任务之外。
CoreResult ResultFromCode(int32_t value)
{
    const auto code = static_cast<CoreErrorCode>(value);
    if (code == CoreErrorCode::OK) {
        return {code, ""};
    }
#ifdef NLASH_HAS_GO_CORE
    char *rawMessage = NlashCoreLastError();
    if (rawMessage == nullptr) {
        return {code, "core operation failed"};
    }
    std::string message(rawMessage);
    NlashCoreFree(rawMessage);
    return {code, message};
#else
    return {CoreErrorCode::UNAVAILABLE, "Go core is unavailable for this ABI"};
#endif
}

} // namespace

std::string CoreVersion()
{
#ifdef NLASH_HAS_GO_CORE
    char *value = NlashCoreVersion();
    if (value == nullptr) {
        return "unknown";
    }
    std::string result(value);
    NlashCoreFree(value);
    return result;
#else
    return "unavailable/non-arm64";
#endif
}

CoreResult ValidateCoreConfig(const std::string &configPath)
{
#ifdef NLASH_HAS_GO_CORE
    return ResultFromCode(NlashCoreValidateConfig(const_cast<char *>(configPath.c_str())));
#else
    (void)configPath;
    return {CoreErrorCode::UNAVAILABLE, "Go core is unavailable for this ABI"};
#endif
}

CoreResult StartCore(const CoreStartOptions &options)
{
#ifdef NLASH_HAS_GO_CORE
    return ResultFromCode(NlashCoreStart(
        const_cast<char *>(options.configPath.c_str()),
        const_cast<char *>(options.workDir.c_str())));
#else
    (void)options;
    return {CoreErrorCode::UNAVAILABLE, "Go core is unavailable for this ABI"};
#endif
}

CoreResult EnableCoreProxy(const CoreProxyOptions &options)
{
    if (options.tunFd < 0) {
        return {CoreErrorCode::INVALID_ARGUMENT, "TUN fd is invalid"};
    }
#ifdef NLASH_HAS_GO_CORE
    // 成功时副本交由 Go TUN 管理；失败时在此关闭，平台原始 FD 始终归宿主所有。
    const int duplicateFd = dup(options.tunFd);
    if (duplicateFd < 0) {
        return {CoreErrorCode::START_FAILED, "failed to duplicate TUN fd"};
    }
    const int32_t code = NlashCoreEnableProxy(
        duplicateFd,
        options.mtu,
        const_cast<char *>(options.protectSocketPath.c_str()),
        const_cast<char *>(options.generation.c_str()));
    if (code != static_cast<int32_t>(CoreErrorCode::OK)) {
        close(duplicateFd);
    }
    return ResultFromCode(code);
#else
    return {CoreErrorCode::UNAVAILABLE, "Go core is unavailable for this ABI"};
#endif
}

CoreResult DisableCoreProxy()
{
#ifdef NLASH_HAS_GO_CORE
    return ResultFromCode(NlashCoreDisableProxy());
#else
    return {CoreErrorCode::UNAVAILABLE, "Go core is unavailable for this ABI"};
#endif
}

bool IsCoreProxyEnabled()
{
#ifdef NLASH_HAS_GO_CORE
    return NlashCoreProxyEnabled() != 0;
#else
    return false;
#endif
}

CoreResult StopCore()
{
#ifdef NLASH_HAS_GO_CORE
    return ResultFromCode(NlashCoreStop());
#else
    return {CoreErrorCode::UNAVAILABLE, "Go core is unavailable for this ABI"};
#endif
}

CoreRuntimeState GetCoreState()
{
#ifdef NLASH_HAS_GO_CORE
    return static_cast<CoreRuntimeState>(NlashCoreState());
#else
    return CoreRuntimeState::FAILED;
#endif
}

std::string ExecuteCoreCommand(const std::string &command)
{
#ifdef NLASH_HAS_GO_CORE
    char *value = NlashCoreExecuteCommand(const_cast<char *>(command.c_str()));
    if (value == nullptr) {
        return R"({"ok":false,"code":"INTERNAL_ERROR","message":"command returned no data"})";
    }
    std::string result(value);
    NlashCoreFree(value);
    return result;
#else
    (void)command;
    return R"({"ok":false,"code":"UNAVAILABLE","message":"Go core is unavailable for this ABI"})";
#endif
}

} // namespace nlash
