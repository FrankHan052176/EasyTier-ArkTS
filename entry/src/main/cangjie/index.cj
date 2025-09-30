package ohos_app_cangjie_entry

import ohos.ark_interop.*
import ohos.ark_interop_macro.*
import serialization.serialization.*
import cangjie_toml.cangjie_toml.*
import encoding.json.*

@Interop[ArkTS]
public func toml2json(toml: String): String {
    let dataModel = toml |> DataModel.fromTomlNext
    return dataModel.toJson().toJsonString()
}
