import { sendFormId } from '../../../util/WidgetAction'
const localStorage = new LocalStorage()

@Entry(localStorage)
@Component
struct Favorite_widgetCard {
  @Watch("updateFormId") @LocalStorageProp('formId') formId: string = 'formId'
  @LocalStorageProp('dim') dim: number = 1
  @LocalStorageProp('favorite_name') favorite_name: string = 'Name'
  @LocalStorageProp('favorite_uuid') favorite_uuid: string = 'UUID'
  @LocalStorageProp('favorite_running') favorite_running: boolean = false

  updateFormId() {
    sendFormId(this, this.formId)
  }

  build() {
    Column() {
      Text(this.formId)
      Text(""+this.dim)
      Text(this.favorite_name)
      Text(this.favorite_uuid)
      Text(""+this.favorite_running)
    }
    .width('100%')
    .height('100%')
    .onClick(() => {

    })
  }
}