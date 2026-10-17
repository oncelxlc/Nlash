import { accessibility } from '@kit.AccessibilityKit';

/** 尊重系统“减少动画”偏好，统一选择控件的过渡参数。 */
export function selectionAnimation(): AnimateParam {
  let duration = 180;
  try {
    if (accessibility.isAnimationReduceEnabledSync()) {
      duration = 0;
    }
  } catch (error) {
    // Older systems may not expose the reduced animation preference.
  }
  return { duration: duration, curve: Curve.EaseOut };
}
