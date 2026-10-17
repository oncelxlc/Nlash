#ifndef NLASH_CORE_BRIDGE_H
#define NLASH_CORE_BRIDGE_H

#include <string>
#include <cstdint>

namespace nlash {

// 数值跨越 Go C ABI 与 ArkTS 映射表，调整顺序时必须同步所有层。
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

// 桥接层拥有错误文本副本，调用方不需要管理 Go 返回的 C 字符串。
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

// tunFd 由 HarmonyOS 持有；EnableCoreProxy 内部复制后才交给 Go。
struct CoreProxyOptions {
    int32_t tunFd = -1;
    int32_t mtu = 0;
    std::string protectSocketPath;
    std::string generation;
};

// 未链接 Go 预编译库的 ABI 返回 unavailable/non-arm64，供上层阻止启动。
std::string CoreVersion();
CoreResult ValidateCoreConfig(const std::string &configPath);
// Core 启停与系统代理启停分离，关闭代理后仍可执行 Core 业务命令。
CoreResult StartCore(const CoreStartOptions &options);
CoreResult EnableCoreProxy(const CoreProxyOptions &options);
CoreResult DisableCoreProxy();
bool IsCoreProxyEnabled();
CoreResult StopCore();
CoreRuntimeState GetCoreState();
std::string ExecuteCoreCommand(const std::string &command);

} // namespace nlash

#endif // NLASH_CORE_BRIDGE_H
