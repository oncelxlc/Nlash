import { accessibility } from '@kit.AccessibilityKit';

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
