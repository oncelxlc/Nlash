import { accessibility } from '@kit.AccessibilityKit';

/** 尊重系统“减少动画”偏好，共用缓动并按交互类型设置时长。 */
export function selectionAnimation(duration: number = 180): AnimateParam {
  try {
    if (accessibility.isAnimationReduceEnabledSync()) {
      duration = 0;
    }
  } catch (error) {
    // Older systems may not expose the reduced animation preference.
  }
  return { duration: duration, curve: Curve.EaseOut };
}

/** 出场更快；由声明式转场持有离场节点，快速返回无需等待完成回调。 */
export function detailTransition(slide: boolean = true): TransitionEffect {
  const enter = TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: slide ? 40 : 0 }));
  const leave = TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: slide ? 40 : 0 }));
  return TransitionEffect.asymmetric(enter.animation(selectionAnimation(280)),
    leave.animation(selectionAnimation(180)));
}

export function revealTransition(): TransitionEffect {
  return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -6 }))
    .animation(selectionAnimation());
}
