import { insightIntent, InsightIntentExecutor } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 意图调用样例
 */
export default class InsightIntentExecutorImpl extends InsightIntentExecutor {
  private static readonly JUMP_FUNCTION_PAGE = 'JumpFunctionPage';

  /**
   * override 执行前台UIAbility意图
   *
   * @param name 意图名称
   * @param param 意图参数
   * @param pageLoader 窗口
   * @returns 意图调用结果
   */
  onExecuteInUIAbilityForegroundMode(name: string, param: Record<string, Object>, pageLoader: window.WindowStage):
    Promise<insightIntent.ExecuteResult> {
    // 根据意图名称分发处理逻辑。接入方可根据实际业务实现页面跳转
    switch (name) {
      case InsightIntentExecutorImpl.JUMP_FUNCTION_PAGE:
        return this.jumpFunctionPage(param, pageLoader);
      default:
        break;
    }
    const data: insightIntent.ExecuteResult = {
      code: -1,
      result: {
        message: 'unknown intent'
      }
    }
    return Promise.resolve(data);
  }

  /**
   * 实现跳转目标页面的功能
   *
   * @param param 意图参数
   * @param pageLoader 窗口
   */
  private jumpFunctionPage(param: Record<string, Object>,
    pageLoader: window.WindowStage): Promise<insightIntent.ExecuteResult> {
    return new Promise((resolve, reject) => {
      if (typeof param?.pageId !== 'string') {
        const data: insightIntent.ExecuteResult = {
          code: -1,
          result: {
            message: 'pageId type error'
          }
        }
        resolve(data);
      }
      let pageId: string = param?.pageId as string;
      pageLoader.loadContent('pages/' + pageId)
        .then(() => {
          const data: insightIntent.ExecuteResult = {
            code: 0,
            result: {
              message: 'Intent execute success'
            }
          }
          resolve(data);
        })
        .catch((err: BusinessError) => {
          // TODO 调用失败的情况
          console.info(`Intent execute failed, Code: ${err?.code}, message: ${err?.message}`);
          const data: insightIntent.ExecuteResult = {
            code: -2,
            result: {
              message: 'Intent execute failed'
            }
          }
          reject(data)
        });
    })
  }
}
