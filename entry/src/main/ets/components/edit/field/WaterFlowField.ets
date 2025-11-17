import { FieldValue } from "../../../class/config/Basic";
import { FieldValueDataSource } from "../../../class/FieldValueDataSource";
import { DataUtil } from "../../../DataUtil";
import { NetworkConfig } from "../../../protobuf/api_manage";
import { lane } from "../../../util/Conversion";
import { ListFieldValue } from "../ListFieldValue";

@ComponentV2
export struct WaterFlowField {
  @Param @Require config: NetworkConfig;
  @Param @Require field: string;
  @Param @Require type: string;
  @Local dataSource: FieldValueDataSource = DataUtil.getDataSource(this.type)

  @Computed
  get comp_height() {
    switch (this.type) {
      case "ip":
      case "string":
      case "cidr":
      case "route": {
        if (this.dataSource.totalCount() <= 2) {
          return (lane(1)-20)/3
        }else if (this.dataSource.totalCount() <= 4) {
          return (lane(1)-20)/3*2+10
        }else {
          return lane(1)
        }
      }
      default: {
        if (this.dataSource.totalCount() <= 2) {
          return (lane(1)-10)/2
        }else {
          return lane(1)
        }
      }
    }
  }

  build() {
    WaterFlow() {
      LazyForEach(this.dataSource, (item: FieldValue) => {
        ListFieldValue({config: this.config, field: this.field, type: this.type, item: item})
      })
    }
    .layoutDirection(FlexDirection.Column)
    .columnsTemplate("1fr 1fr")
    .columnsGap(10)
    .rowsGap(10)
    .height(this.comp_height)
    .width('100%')
  }
}