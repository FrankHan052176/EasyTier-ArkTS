package ohos_app_cangjie_entry

internal import ohos.ark_interop.JSModule
internal import ohos.ark_interop.JSContext
internal import ohos.ark_interop.JSCallInfo
internal import ohos.ark_interop.JSValue
internal import cj_res_entry.app
import serialization.serialization.*
import cangjie_toml.cangjie_toml.*
import encoding.json.*

func toml2json(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let toml = callInfo[0].toString(runtime)
    let dataModel = toml |> DataModel.fromTomlNext
    runtime.string(dataModel.toJson().toJsonString()).toJSValue()
}


let EXPORT_MODULE = JSModule.registerModule {
    runtime, exports => exports["toml2json"] = runtime.function(toml2json).toJSValue()
}
