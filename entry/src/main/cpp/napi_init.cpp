#include "napi/native_api.h"
#include <iostream>
#include <vector>
#include <string>
#include "hilog/log.h"
#include <toml++/toml.hpp>
#include <nlohmann/json.hpp>
#include "layout.hpp"
std::vector<std::string> appLog;
std::vector<std::string> nmLog;
std::vector<std::string> ohLog;
Layout layout(1,8);
void MyHiLog(const LogType type, const LogLevel level, const unsigned int domain, const char *tag, const char *msg)
{
    if (level >= LOG_INFO && strcmp(tag, "fhl") == 0) {
        appLog.push_back(std::to_string(static_cast<int>(level))+msg);
    }else if (level >= LOG_WARN && strcmp(tag, "NETMANAGER_EXT") == 0) {
        std::string safeMsg;
        safeMsg = std::string("[NETMANAGER_EXT] ") + msg;
        nmLog.push_back(std::to_string(static_cast<int>(level))+safeMsg);
    }else if (level >= LOG_ERROR) {
        ohLog.push_back(std::to_string(static_cast<int>(level))+msg);
    }
}
static napi_value hilogInit(napi_env env, napi_callback_info info)
{
    OH_LOG_SetCallback(MyHiLog);
    return NULL;
}
static napi_value getAppLog(napi_env env, napi_callback_info info)
{
    napi_value output_array;
    napi_create_array(env, &output_array);
    for (size_t i = 0; i < appLog.size(); i++) {
        napi_value jsString;
        // C++ string 转 JS string
        napi_create_string_utf8(env, appLog[i].c_str(), NAPI_AUTO_LENGTH, &jsString);
        // 设置到 array[i]
        napi_set_element(env, output_array, i, jsString);
    }
    return output_array;
}
static napi_value getNetworkManagerLog(napi_env env, napi_callback_info info)
{
    napi_value output_array;
    napi_create_array(env, &output_array);
    for (size_t i = 0; i < nmLog.size(); i++) {
        napi_value jsString;
        // C++ string 转 JS string
        napi_create_string_utf8(env, nmLog[i].c_str(), NAPI_AUTO_LENGTH, &jsString);
        // 设置到 array[i]
        napi_set_element(env, output_array, i, jsString);
    }
    return output_array;
}
static napi_value getOHLog(napi_env env, napi_callback_info info)
{
    napi_value output_array;
    napi_create_array(env, &output_array);
    for (size_t i = 0; i < ohLog.size(); i++) {
        napi_value jsString;
        // C++ string 转 JS string
        napi_create_string_utf8(env, ohLog[i].c_str(), NAPI_AUTO_LENGTH, &jsString);
        // 设置到 array[i]
        napi_set_element(env, output_array, i, jsString);
    }
    return output_array;
}
static napi_value toml2json(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    size_t length = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &length);
    char* buf = new char[length + 1];
    std::memset(buf, 0, length + 1);
    napi_get_value_string_utf8(env, args[0], buf, length + 1, &length);
    // 转换配置
    napi_value result = nullptr;
    std::ostringstream oss;
    try {
        auto table = toml::parse(buf);
        oss << toml::json_formatter{ table };
    } catch (...) {
        oss << "ERROR";
    }
    napi_create_string_utf8(env, oss.str().c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}
static napi_value updateLayout(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    layout.
    return NULL;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "getAppLog", nullptr, getAppLog, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getNetworkManagerLog", nullptr, getNetworkManagerLog, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getOHLog", nullptr, getOHLog, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "hilogInit", nullptr, hilogInit, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "toml2json", nullptr, toml2json, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
