#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>

#include <arkui/native_interface.h>
#include <arkui/native_node.h>
#include <arkui/native_node_napi.h>
#include <hitrace/trace.h>
#include <napi/native_api.h>

namespace {

class ScopedTrace final {
public:
    explicit ScopedTrace(const char *name)
    {
        OH_HiTrace_StartTrace(name);
    }

    ~ScopedTrace()
    {
        OH_HiTrace_FinishTrace();
    }
};

struct BoolTextModel {
    std::string category;
    std::string text;
    float width = 0.0F;
    float height = 0.0F;
    uint32_t categoryColor = 0;
    uint32_t textColor = 0;
};

struct BoolTextRecord {
    ArkUI_NodeContentHandle content = nullptr;
    ArkUI_NodeHandle root = nullptr;
    ArkUI_NodeHandle category = nullptr;
    ArkUI_NodeHandle text = nullptr;
    std::string categoryValue;
    std::string textValue;
};

struct EnvState {
    std::unordered_map<ArkUI_NodeContentHandle, std::unique_ptr<BoolTextRecord>> records;
};

ArkUI_NativeNodeAPI_1 *g_nodeApi = nullptr;

ArkUI_NativeNodeAPI_1 *GetNodeApi()
{
    if (g_nodeApi == nullptr) {
        OH_ArkUI_GetModuleInterface(ARKUI_NATIVE_NODE, ArkUI_NativeNodeAPI_1, g_nodeApi);
    }
    return g_nodeApi;
}

bool SetFloat(ArkUI_NodeHandle node, ArkUI_NodeAttributeType type, float value)
{
    ArkUI_NumberValue number[1] = {};
    number[0].f32 = value;
    ArkUI_AttributeItem item = {};
    item.value = number;
    item.size = 1;
    auto *api = GetNodeApi();
    return api != nullptr && api->setAttribute(node, type, &item) == ARKUI_ERROR_CODE_NO_ERROR;
}

bool SetInt(ArkUI_NodeHandle node, ArkUI_NodeAttributeType type, int32_t value)
{
    ArkUI_NumberValue number[1] = {};
    number[0].i32 = value;
    ArkUI_AttributeItem item = {};
    item.value = number;
    item.size = 1;
    auto *api = GetNodeApi();
    return api != nullptr && api->setAttribute(node, type, &item) == ARKUI_ERROR_CODE_NO_ERROR;
}

bool SetColor(ArkUI_NodeHandle node, ArkUI_NodeAttributeType type, uint32_t value)
{
    ArkUI_NumberValue number[1] = {};
    number[0].u32 = value;
    ArkUI_AttributeItem item = {};
    item.value = number;
    item.size = 1;
    auto *api = GetNodeApi();
    return api != nullptr && api->setAttribute(node, type, &item) == ARKUI_ERROR_CODE_NO_ERROR;
}

bool SetString(ArkUI_NodeHandle node, ArkUI_NodeAttributeType type, const std::string &value)
{
    ArkUI_AttributeItem item = {};
    item.string = value.c_str();
    auto *api = GetNodeApi();
    return api != nullptr && api->setAttribute(node, type, &item) == ARKUI_ERROR_CODE_NO_ERROR;
}

bool GetNamedValue(napi_env env, napi_value object, const char *name, napi_value *result)
{
    bool hasProperty = false;
    if (napi_has_named_property(env, object, name, &hasProperty) != napi_ok || !hasProperty) {
        return false;
    }
    return napi_get_named_property(env, object, name, result) == napi_ok;
}

bool GetNamedString(napi_env env, napi_value object, const char *name, std::string *result)
{
    napi_value value = nullptr;
    if (!GetNamedValue(env, object, name, &value)) {
        return false;
    }
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    std::string text(length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, text.data(), text.size(), &copied) != napi_ok) {
        return false;
    }
    text.resize(copied);
    *result = std::move(text);
    return true;
}

bool GetNamedDouble(napi_env env, napi_value object, const char *name, double *result)
{
    napi_value value = nullptr;
    return GetNamedValue(env, object, name, &value) && napi_get_value_double(env, value, result) == napi_ok;
}

bool ReadModel(napi_env env, napi_value value, BoolTextModel *model)
{
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_object) {
        return false;
    }
    double width = 0.0;
    double height = 0.0;
    double categoryColor = 0.0;
    double textColor = 0.0;
    if (!GetNamedString(env, value, "category", &model->category) ||
        !GetNamedString(env, value, "text", &model->text) ||
        !GetNamedDouble(env, value, "width", &width) ||
        !GetNamedDouble(env, value, "height", &height) ||
        !GetNamedDouble(env, value, "categoryColor", &categoryColor) ||
        !GetNamedDouble(env, value, "textColor", &textColor)) {
        return false;
    }
    model->width = std::max(0.0F, static_cast<float>(width));
    model->height = std::max(0.0F, static_cast<float>(height));
    model->categoryColor = static_cast<uint32_t>(categoryColor);
    model->textColor = static_cast<uint32_t>(textColor);
    return true;
}

bool ApplyModel(BoolTextRecord &record, const BoolTextModel &model)
{
    record.categoryValue = model.category;
    record.textValue = model.text;

    bool success = SetFloat(record.root, NODE_WIDTH, model.width);
    success = SetFloat(record.root, NODE_HEIGHT, model.height) && success;
    success = SetInt(record.root, NODE_COLUMN_ALIGN_ITEMS, ARKUI_HORIZONTAL_ALIGNMENT_START) && success;
    success = SetInt(record.root, NODE_COLUMN_JUSTIFY_CONTENT, ARKUI_FLEX_ALIGNMENT_SPACE_BETWEEN) && success;

    success = SetFloat(record.category, NODE_WIDTH, model.width) && success;
    success = SetString(record.category, NODE_TEXT_CONTENT, record.categoryValue) && success;
    success = SetFloat(record.category, NODE_FONT_SIZE, 12.0F) && success;
    success = SetColor(record.category, NODE_FONT_COLOR, model.categoryColor) && success;
    success = SetInt(record.category, NODE_TEXT_MAX_LINES, 1) && success;
    success = SetInt(record.category, NODE_TEXT_ALIGN, ARKUI_TEXT_ALIGNMENT_START) && success;
    success = SetInt(record.category, NODE_TEXT_OVERFLOW, ARKUI_TEXT_OVERFLOW_ELLIPSIS) && success;

    success = SetFloat(record.text, NODE_WIDTH, model.width) && success;
    success = SetString(record.text, NODE_TEXT_CONTENT, record.textValue) && success;
    success = SetFloat(record.text, NODE_FONT_SIZE, 16.0F) && success;
    success = SetColor(record.text, NODE_FONT_COLOR, model.textColor) && success;
    success = SetInt(record.text, NODE_TEXT_MAX_LINES, 1) && success;
    success = SetInt(record.text, NODE_TEXT_ALIGN, ARKUI_TEXT_ALIGNMENT_START) && success;
    success = SetInt(record.text, NODE_TEXT_OVERFLOW, ARKUI_TEXT_OVERFLOW_ELLIPSIS) && success;
    return success;
}

void DisposeRecord(BoolTextRecord &record)
{
    auto *api = GetNodeApi();
    if (api == nullptr) {
        return;
    }
    if (record.content != nullptr && record.root != nullptr) {
        OH_ArkUI_NodeContent_RemoveNode(record.content, record.root);
    }
    if (record.root != nullptr && record.category != nullptr) {
        api->removeChild(record.root, record.category);
    }
    if (record.root != nullptr && record.text != nullptr) {
        api->removeChild(record.root, record.text);
    }
    if (record.category != nullptr) {
        api->disposeNode(record.category);
        record.category = nullptr;
    }
    if (record.text != nullptr) {
        api->disposeNode(record.text);
        record.text = nullptr;
    }
    if (record.root != nullptr) {
        api->disposeNode(record.root);
        record.root = nullptr;
    }
    record.content = nullptr;
}

bool CreateRecord(EnvState &state, ArkUI_NodeContentHandle content, const BoolTextModel &model)
{
    ScopedTrace trace("ET_BOOL_NATIVE_CREATE");
    auto *api = GetNodeApi();
    if (api == nullptr || content == nullptr) {
        return false;
    }
    auto record = std::make_unique<BoolTextRecord>();
    record->content = content;
    record->root = api->createNode(ARKUI_NODE_COLUMN);
    record->category = api->createNode(ARKUI_NODE_TEXT);
    record->text = api->createNode(ARKUI_NODE_TEXT);
    if (record->root == nullptr || record->category == nullptr || record->text == nullptr) {
        DisposeRecord(*record);
        return false;
    }
    if (api->addChild(record->root, record->category) != ARKUI_ERROR_CODE_NO_ERROR ||
        api->addChild(record->root, record->text) != ARKUI_ERROR_CODE_NO_ERROR) {
        DisposeRecord(*record);
        return false;
    }
    if (!ApplyModel(*record, model)) {
        DisposeRecord(*record);
        return false;
    }
    if (OH_ArkUI_NodeContent_AddNode(content, record->root) != ARKUI_ERROR_CODE_NO_ERROR) {
        DisposeRecord(*record);
        return false;
    }
    state.records.emplace(content, std::move(record));
    return true;
}

bool UpdateOrCreate(EnvState &state, ArkUI_NodeContentHandle content, const BoolTextModel &model)
{
    auto found = state.records.find(content);
    if (found == state.records.end()) {
        return CreateRecord(state, content, model);
    }
    ScopedTrace trace("ET_BOOL_NATIVE_UPDATE");
    if (ApplyModel(*found->second, model)) {
        return true;
    }
    DisposeRecord(*found->second);
    state.records.erase(found);
    return false;
}

napi_value BooleanResult(napi_env env, bool value)
{
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

bool ReadArguments(napi_env env, napi_callback_info info, EnvState **state,
    ArkUI_NodeContentHandle *content, BoolTextModel *model)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    void *data = nullptr;
    if (napi_get_cb_info(env, info, &argc, args, nullptr, &data) != napi_ok || argc < 2 || data == nullptr) {
        return false;
    }
    *state = static_cast<EnvState *>(data);
    *content = nullptr;
    if (OH_ArkUI_GetNodeContentFromNapiValue(env, args[0], content) != ARKUI_ERROR_CODE_NO_ERROR ||
        *content == nullptr) {
        return false;
    }
    return ReadModel(env, args[1], model);
}

napi_value CreateBoolText(napi_env env, napi_callback_info info)
{
    EnvState *state = nullptr;
    ArkUI_NodeContentHandle content = nullptr;
    BoolTextModel model;
    if (!ReadArguments(env, info, &state, &content, &model)) {
        return BooleanResult(env, false);
    }
    return BooleanResult(env, UpdateOrCreate(*state, content, model));
}

napi_value UpdateBoolText(napi_env env, napi_callback_info info)
{
    EnvState *state = nullptr;
    ArkUI_NodeContentHandle content = nullptr;
    BoolTextModel model;
    if (!ReadArguments(env, info, &state, &content, &model)) {
        return BooleanResult(env, false);
    }
    return BooleanResult(env, UpdateOrCreate(*state, content, model));
}

napi_value DestroyBoolText(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    void *data = nullptr;
    napi_get_cb_info(env, info, &argc, args, nullptr, &data);
    auto *state = static_cast<EnvState *>(data);
    if (argc == 1 && state != nullptr) {
        ArkUI_NodeContentHandle content = nullptr;
        if (OH_ArkUI_GetNodeContentFromNapiValue(env, args[0], &content) == ARKUI_ERROR_CODE_NO_ERROR) {
            auto found = state->records.find(content);
            if (found != state->records.end()) {
                ScopedTrace trace("ET_BOOL_NATIVE_DESTROY");
                DisposeRecord(*found->second);
                state->records.erase(found);
            }
        }
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

void Cleanup(void *data)
{
    auto *state = static_cast<EnvState *>(data);
    if (state == nullptr) {
        return;
    }
    for (auto &entry : state->records) {
        DisposeRecord(*entry.second);
    }
    delete state;
}

napi_value Init(napi_env env, napi_value exports)
{
    auto *state = new EnvState();
    napi_property_descriptor descriptors[] = {
        {"createBoolText", nullptr, CreateBoolText, nullptr, nullptr, nullptr, napi_default, state},
        {"updateBoolText", nullptr, UpdateBoolText, nullptr, nullptr, nullptr, napi_default, state},
        {"destroyBoolText", nullptr, DestroyBoolText, nullptr, nullptr, nullptr, napi_default, state},
    };
    if (napi_add_env_cleanup_hook(env, Cleanup, state) != napi_ok) {
        delete state;
        return exports;
    }
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}

} // namespace

static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "easytier_ui",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

extern "C" __attribute__((constructor)) void RegisterEasyTierUiModule()
{
    napi_module_register(&g_module);
}
