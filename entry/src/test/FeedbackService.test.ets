import { describe, expect, it } from '@ohos/hypium';
import { FeedbackEvent, FeedbackLevel } from '../main/ets/model/FeedbackModels';
import { FeedbackService } from '../main/ets/services/FeedbackService';

export default function feedbackServiceTest() {
  describe('feedbackService', () => {
    it('publishesTypedEventsWithIncreasingIds', 0, () => {
      const service = new FeedbackService();
      const events: FeedbackEvent[] = [];
      const unsubscribe = service.subscribe((event: FeedbackEvent): void => {
        events.push(event);
      });
      service.info('准备中');
      service.success('完成');
      unsubscribe();

      expect(events.length).assertEqual(2);
      expect(events[0].level).assertEqual(FeedbackLevel.INFO);
      expect(events[1].level).assertEqual(FeedbackLevel.SUCCESS);
      expect(events[1].id > events[0].id).assertTrue();
    });

    it('deduplicatesRepeatedBackgroundFeedback', 0, () => {
      const service = new FeedbackService();
      let count = 0;
      service.subscribe((_event: FeedbackEvent): void => { count += 1; });
      service.publishDeduplicated(FeedbackLevel.ERROR, '连接失败', 60000);
      service.publishDeduplicated(FeedbackLevel.ERROR, '连接失败', 60000);
      service.publishDeduplicated(FeedbackLevel.ERROR, '另一错误', 60000);

      expect(count).assertEqual(2);
    });
  });
}
