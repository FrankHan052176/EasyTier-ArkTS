import { CidrEditor } from "../../class/config/Cidr"
import { IPEditor } from "../../class/config/IP"
import { NetworkNameEditor } from "../../class/config/NetworkName"
import { UrlEditor } from "../../class/config/Url"
import { AddTitle, EditTitle } from "./AddAndEditTitle"
import { NewConfig_Content, NewConfig_Title } from "./NewConfig"
import { Setting_Sheet, Setting_Title } from "./Settings"

@Builder
export function SheetContentBuilder(type: string) {
  SheetContent({type: type})
}

@Builder
export function SheetTitleBuilder(type: string) {
  Row() {
    SheetTitle({type: type})
      .width('100%')
      .height('100%')
  }
  .width('100%')
  .height('100%')
}

@ComponentV2
export struct SheetContent {
  @Param @Require type: string

  @Computed
  get addFieldType() {
    return this.type.substring(4).substring(0, this.type.substring(4).indexOf('_'))
  }

  @Computed
  get addFieldName() {
    return this.type.substring(4).substring(this.type.substring(4).indexOf('_')+1)
  }

  @Computed
  get editFieldType() {
    return this.type.substring(5).substring(0, this.type.substring(5).indexOf('_'))
  }

  @Computed
  get editFieldName() {
    return this.type.substring(5).substring(this.type.substring(5).indexOf('_')+1)
  }

  build() {
    if (this.type === "new") {
      NewConfig_Content()
    }else if (this.type === "setting") {
      Setting_Sheet()
    }else if (this.type.startsWith("add_")) {
      if (this.addFieldType === "cidr" || this.addFieldType === "route") {
        CidrEditor()
      }else if (this.addFieldType === "peer" || this.addFieldType === "listener" || this.addFieldType === "mappedListener") {
        UrlEditor()
      }else if (this.addFieldType === "ip") {
        IPEditor()
      }else if (this.addFieldType === "string") {
        NetworkNameEditor()
      }else if (this.addFieldType === "port_forward") {
        // TODO 端口转发的编辑组件
      }
    }else if (this.type.startsWith("edit_")) {
      if (this.editFieldType === "cidr" || this.editFieldType === "route") {
        CidrEditor()
      }else if (this.editFieldType === "peer" || this.editFieldType === "listener" || this.editFieldType === "mappedListener") {
        UrlEditor()
      }else if (this.editFieldType === "ip") {
        IPEditor()
      }else if (this.editFieldType === "string") {
        NetworkNameEditor()
      }else if (this.editFieldType === "port_forward") {
        // TODO 端口转发的编辑组件
      }
    }else {
      Text(this.type)
    }
  }
}

@ComponentV2
export struct SheetTitle {
  @Param @Require type: string

  @Computed
  get addFieldType() {
    return this.type.substring(4).substring(0, this.type.substring(4).indexOf('_'))
  }

  @Computed
  get addFieldName() {
    return this.type.substring(4).substring(this.type.substring(4).indexOf('_')+1)
  }

  @Computed
  get editFieldType() {
    return this.type.substring(5).substring(0, this.type.substring(5).indexOf('_'))
  }

  @Computed
  get editFieldName() {
    return this.type.substring(5).substring(this.type.substring(5).indexOf('_')+1)
  }

  build() {
    if (this.type === "new") {
      NewConfig_Title()
    }else if (this.type === "setting") {
      Setting_Title()
    }else if (this.type.startsWith("add_")) {
      AddTitle({fieldType: this.addFieldType, fieldName: this.addFieldName})
    }else if (this.type.startsWith("edit_")) {
      EditTitle({fieldType: this.editFieldType, fieldName: this.editFieldName})
    }else {
      Text(this.type)
    }
  }
}