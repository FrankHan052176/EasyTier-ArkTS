import { HMAnimator, HMAnimatorHandle, IHMAnimator } from "@hadss/hmrouter";
import { AttributeUpdater } from "@kit.ArkUI";

@HMAnimator({ animatorName: 'CustomAnimator' })
export class BottomAnimator implements IHMAnimator {
  effect(enterHandle: HMAnimatorHandle, exitHandle: HMAnimatorHandle): void {
    // to animator
    enterHandle.start((modifier: AttributeUpdater<NavDestinationAttribute>) => {
      modifier.attribute?.translate({ y: '100%' }).scale({ x: 0.7 }).opacity(0.3)
    }).finish((modifier: AttributeUpdater<NavDestinationAttribute>) => {
      modifier.attribute?.translate({ y: '0' }).scale({ x: 1 }).opacity(1)
    })
    enterHandle.duration = 400;
    enterHandle.curve = Curve.Linear;

    // cut animator
    exitHandle.start((modifier: AttributeUpdater<NavDestinationAttribute>) => {
      modifier.attribute?.translate({ y: '0' }).scale({ x: 1 }).opacity(1)
    }).finish((modifier: AttributeUpdater<NavDestinationAttribute>) => {
      modifier.attribute?.translate({ y: '100%' }).scale({ x: 0.7 }).opacity(0.3)
    })
    exitHandle.duration = 400;
    enterHandle.curve = Curve.Linear;
  }
}