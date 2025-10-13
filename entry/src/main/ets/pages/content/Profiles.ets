import Manager from "../../Manager"
import { Config, network_identity } from "../../util/config/ETConfig"
import { FancyItem } from "../Components"
import { hashString, hashToColor, safePassword } from "../../util/Conversion"
import Logger from "../../util/Logger"
const minWidth = 350

@ComponentV2
export struct Profiles {
  @Param @Require config: Config
  @Local item_width: number = 90
  @Local item_height: number = 110
  @Local edit: network_identity = new network_identity()
  @Local add: network_identity = new network_identity()
  @Local old: network_identity = new network_identity()
  @Local isBig: boolean = false

  @Computed
  get comp_width() {
    return Manager.width>=Manager.height*0.625?minWidth:Manager.width-20
  }

  @Builder
  ProfileSheet(Profile:network_identity) {
    Column() {
      Text("名称")
        .width('100%')
        .align(Alignment.Start)
        .fontSize(14)
        .fontColor($r("sys.color.font_secondary"))
        .margin({bottom:5})
      TextInput({ text: Profile.network_name})
        .borderRadius(10)
        .margin({bottom:10})
        .type(InputType.USER_NAME)
        .onChange((value) => {
          Profile.network_name = value
        })
      Text("密码")
        .width('100%')
        .align(Alignment.Start)
        .fontSize(14)
        .fontColor($r("sys.color.font_secondary"))
        .margin({bottom:5})
      TextInput({ text: Profile.network_secret})
        .borderRadius(10)
        .margin({bottom:10})
        .type(InputType.Password)
        .onChange((value) => {
          Profile.network_secret = value
        })
      Text(`
凭证分为名称与密码，等同于网络名称与网络密码
      `)
        .width('100%')
        .fontSize(14)
        .fontColor($r("sys.color.font_secondary"))
        .textAlign(TextAlign.Center)
      Blank()
        .width('100%')
        .height(100)
    }
    .width('90%')
  }

  @Builder
  profileContent(value: network_identity) {
    Row() {
      Text(value.network_name.charAt(0).toUpperCase())
        .fontSize(20)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Bold)
    }
    .borderRadius(360)
    .backgroundColor(hashToColor(hashString(value.network_name)))
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width(50)
    .height(50)
    .margin({
      top: 15,
      bottom: 15
    })
    Text(value.network_name)
      .width(70)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontSize(14)
      .fontColor($r("sys.color.font_primary"))
      .textAlign(TextAlign.Center)
      .geometryTransition(this.config.instance_id+"_profile_name_"+value.toString(), {follow: false})
  }

  @Builder
  addContent() {
    Row() {
      SymbolGlyph($r("sys.symbol.plus"))
        .backgroundColor(Color.Transparent)
        .fontSize(20)
        .fontColor([$r("sys.color.font_primary")])
    }
    .borderRadius(360)
    .backgroundColor($r("sys.color.comp_background_tertiary"))
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width(50)
    .height(50)
    .margin({
      top: 15,
      bottom: 15
    })
    Text('新增凭证')
      .width(70)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontSize(16)
      .fontColor($r("sys.color.font_primary"))
      .textAlign(TextAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Text("凭证")
          .fontSize(17)
          .fontColor($r("sys.color.font_primary"))
        Row() {
          Text(this.isBig?"折叠":"展开")
            .fontSize(16)
            .fontColor($r("sys.color.font_primary"))
          SymbolGlyph(this.isBig?$r("sys.symbol.arrow_down_right_and_arrow_up_left"):$r("sys.symbol.arrow_up_left_and_arrow_down_right"))
            .fontColor([$r("sys.color.font_primary")])
            .width(18)
            .height(18)
            .effectStrategy(SymbolEffectStrategy.SCALE)
        }
        .onClick(() => {
          animateToImmediately({
            curve: Curve.LinearOutSlowIn,
            duration: 300
          }, () => {
            this.isBig = !this.isBig
          })
        })
        .clickEffect({
          level: ClickEffectLevel.LIGHT
        })
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .padding({left: 5, bottom: 5})
      if (this.isBig) {
        List({space: 10, initialIndex: 0}) {
          ForEach(Array.from(Manager.network_identities), (value:network_identity) => {
            FancyItem({
              item_width: this.item_width,
              item_height: this.item_height,
              isSingle: true,
              contentBuilder: () => {
                this.profileContent(value)
              },
              sheetBuilder: () => {
                this.ProfileSheet(this.edit)
              },
              clickCallback: () => {
                if (this.config.network_identity.toString() != value.toString()) {
                  this.config.network_identity.from(value)
                }
              },
              changeCallback: (isOn) => {
                if (isOn) {
                  this.config.network_identity.from(value)
                }
              },
              isSelected: () => {
                return this.config.network_identity.toString() == value.toString()
              },
              menuEditCallback: () => {
                this.edit = new network_identity().from(value)
                this.old = new network_identity().from(value)
              },
              menuDeleteCallback: () => {
                Manager.network_identities.delete(value)
              },
              sheetConfirmCallback: () => {
                Manager.configs.forEach((value) => {
                  Manager.network_identities.delete(this.old!)
                  Manager.network_identities.add(this.edit!)
                  if (value.network_identity.toString() == this.old!.toString()) {
                    value.network_identity.from(this.edit!)
                    this.old.reset()
                  }
                })
              },
              sheetTitleFunc: () => {
                return "编辑凭证"
              }
            })
          }, (value:network_identity) => {return this.config.instance_id+"_profile_"+value.toString()})
          FancyItem({
            item_width: this.item_width,
            item_height: this.item_height,
            needCheckbox: false,
            needMenu: false,
            contentBuilder: () => {
              this.addContent()
            },
            sheetBuilder: () => {
              this.ProfileSheet(this.add!)
            },
            sheetConfirmCallback: () => {
              if (!Manager.network_identities.has(this.add!) && this.add!.network_name.match(/^\s*$/) === null) {
                Manager.network_identities.add(new network_identity().from(this.add!))
              }
              this.add.reset()
            },
            sheetTitleFunc: () => {
              return "新增凭证"
            }
          })
        }
        .borderRadius(10)
        .maintainVisibleContentPosition(true)
        .scrollBar(BarState.Off)
        .listDirection(Axis.Horizontal)
        .width('100%')
        .height(this.item_height)
      }else {
        Row() {
          Row() {
            Text(`${this.config.network_identity.network_name}`)
              .fontSize(14)
              .padding({left: 10, top: 10, bottom: 10})
              .geometryTransition(this.config.instance_id+"_profile_name_"+this.config.network_identity.toString())
            Text(`/ ${safePassword(this.config.network_identity.network_secret)}`)
              .fontSize(14)
              .padding({right: 10, top: 10, bottom: 10})
          }
          .borderRadius(10)
          .backgroundColor($r("sys.color.interactive_hover"))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
    }
    .width(this.comp_width)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding(10)
    .clip(true)
  }
}
