#include "napi/native_api.h"
#include <cstring>
#include <string>
#include <vector>
#include "hilog/log.h"
#include "LockFreeRingBuffer.h"

LockFreeRingBuffer<100> appLog;
LockFreeRingBuffer<100> nmLog;

void MyHiLog(const LogType type, const LogLevel level, const unsigned int domain, const char *tag, const char *msg) {
    std::string finalMsg;
    if (level >= LOG_DEBUG && strcmp(tag, "fhl") == 0) {
        finalMsg = std::to_string(static_cast<int>(level)) + msg;
        appLog.write(finalMsg);
    } else if (level >= LOG_WARN && strcmp(tag, "NETMANAGER_EXT") == 0) {
        finalMsg = std::to_string(static_cast<int>(level)) + "[NETMANAGER_EXT] " + msg;
        nmLog.write(finalMsg);
    }
}
static napi_value hilogInit(napi_env env, napi_callback_info info) {
    OH_LOG_SetCallback(MyHiLog);
    return NULL;
}
static napi_value getAppLog(napi_env env, napi_callback_info info) {
    std::vector<std::string> messages = appLog.read_all();
    napi_value output_array;
    napi_status status = napi_create_array(env, &output_array);
    if (status != napi_ok) {
        return nullptr;
    }
    for (size_t i = 0; i < messages.size(); i++) {
        napi_value jsString;
        status = napi_create_string_utf8(env, messages[i].c_str(), NAPI_AUTO_LENGTH, &jsString);
        if (status == napi_ok) {
            napi_set_element(env, output_array, i, jsString);
        }
    }
    return output_array;
}
static napi_value getNetworkManagerLog(napi_env env, napi_callback_info info) {
    std::vector<std::string> messages = nmLog.read_all();
    napi_value output_array;
    napi_status status = napi_create_array(env, &output_array);
    if (status != napi_ok) {
        return nullptr;
    }
    for (size_t i = 0; i < messages.size(); i++) {
        napi_value jsString;
        status = napi_create_string_utf8(env, messages[i].c_str(), NAPI_AUTO_LENGTH, &jsString);
        if (status == napi_ok) {
            napi_set_element(env, output_array, i, jsString);
        }
    }
    return output_array;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"getAppLog", nullptr, getAppLog, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getNetworkManagerLog", nullptr, getNetworkManagerLog, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"hilogInit", nullptr, hilogInit, nullptr, nullptr, nullptr, napi_default, nullptr}};
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
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) { napi_module_register(&demoModule); }
