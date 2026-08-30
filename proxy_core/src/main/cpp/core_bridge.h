#ifndef NLASH_CORE_BRIDGE_H
#define NLASH_CORE_BRIDGE_H

#include <string>
#include <cstdint>

namespace nlash {

enum class CoreErrorCode : int32_t {
    OK = 0,
    INVALID_ARGUMENT = 1,
    INVALID_STATE = 2,
    CONFIG_INVALID = 3,
    PROTECT_FAILED = 4,
    START_FAILED = 5,
    STOP_FAILED = 6,
    INTERNAL_ERROR = 7,
    UNAVAILABLE = 8,
};

enum class CoreRuntimeState : int32_t {
    STOPPED = 0,
    VALIDATING = 1,
    STARTING = 2,
    RUNNING = 3,
    STOPPING = 4,
    FAILED = 5,
};

struct CoreResult {
    CoreErrorCode code;
    std::string message;

    bool IsOk() const
    {
        return code == CoreErrorCode::OK;
    }
};

struct CoreStartOptions {
    std::string configPath;
    std::string workDir;
};

struct CoreProxyOptions {
    int32_t tunFd = -1;
    int32_t mtu = 0;
    std::string protectSocketPath;
    std::string generation;
};

std::string CoreVersion();
CoreResult ValidateCoreConfig(const std::string &configPath);
CoreResult StartCore(const CoreStartOptions &options);
CoreResult EnableCoreProxy(const CoreProxyOptions &options);
CoreResult DisableCoreProxy();
bool IsCoreProxyEnabled();
CoreResult StopCore();
CoreRuntimeState GetCoreState();
std::string ExecuteCoreCommand(const std::string &command);

} // namespace nlash

#endif // NLASH_CORE_BRIDGE_H
