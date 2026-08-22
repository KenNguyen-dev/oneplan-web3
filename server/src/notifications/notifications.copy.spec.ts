import { EngagementLocale } from '@prisma/client';
import { PUSH_COPY, pushLocale } from './notifications.copy';

describe('notifications.copy', () => {
  describe('pushLocale', () => {
    it('returns VN only for VN', () => {
      expect(pushLocale(EngagementLocale.VN)).toBe(EngagementLocale.VN);
    });

    it('defaults to EN for EN, null and undefined', () => {
      expect(pushLocale(EngagementLocale.EN)).toBe(EngagementLocale.EN);
      expect(pushLocale(null)).toBe(EngagementLocale.EN);
      expect(pushLocale(undefined)).toBe(EngagementLocale.EN);
    });
  });

  describe('pinExtractionDone', () => {
    it('localizes the title per locale', () => {
      expect(PUSH_COPY.pinExtractionDone.EN(8).title).toBe('Pins ready!');
      expect(PUSH_COPY.pinExtractionDone.VN(8).title).toBe('Pins đã sẵn sàng!');
    });

    it('pluralizes only on the EN side', () => {
      expect(PUSH_COPY.pinExtractionDone.EN(1).body).toBe('1 pin extracted.');
      expect(PUSH_COPY.pinExtractionDone.EN(8).body).toBe('8 pins extracted.');
      // Vietnamese has no plural inflection.
      expect(PUSH_COPY.pinExtractionDone.VN(1).body).toBe(
        'Đã trích xuất 1 pin.',
      );
      expect(PUSH_COPY.pinExtractionDone.VN(8).body).toBe(
        'Đã trích xuất 8 pin.',
      );
    });

    it('includes and truncates the video title when present', () => {
      const long = 'x'.repeat(80);
      const en = PUSH_COPY.pinExtractionDone.EN(3, long).body;
      const vn = PUSH_COPY.pinExtractionDone.VN(3, long).body;
      expect(en).toBe(`3 pins extracted from "${'x'.repeat(48)}".`);
      expect(vn).toBe(`Đã trích xuất 3 pin từ "${'x'.repeat(48)}".`);
    });

    it('omits the video clause when absent', () => {
      expect(PUSH_COPY.pinExtractionDone.EN(2).body).not.toContain('from');
      expect(PUSH_COPY.pinExtractionDone.VN(2).body).not.toContain('từ');
    });
  });

  describe('pinExtractionFailed', () => {
    it('differs by locale', () => {
      expect(PUSH_COPY.pinExtractionFailed.EN().title).toBe(
        'Extraction failed',
      );
      expect(PUSH_COPY.pinExtractionFailed.VN().title).toBe(
        'Trích xuất thất bại',
      );
    });
  });

  describe('planReminder', () => {
    it('localizes the time connector and keeps the trip name as title', () => {
      const en = PUSH_COPY.planReminder.EN('Đà Lạt', 'Cà phê', '09:45', 'Chợ');
      const vn = PUSH_COPY.planReminder.VN('Đà Lạt', 'Cà phê', '09:45', 'Chợ');
      expect(en.title).toBe('Đà Lạt');
      expect(en.body).toBe('Cà phê at 09:45 • Chợ');
      expect(vn.body).toBe('Cà phê lúc 09:45 • Chợ');
    });

    it('drops the location segment when null', () => {
      expect(PUSH_COPY.planReminder.VN('T', 'I', '10:00', null).body).toBe(
        'I lúc 10:00',
      );
    });
  });

  describe('member and social copy', () => {
    it('interpolates names without translating them', () => {
      expect(PUSH_COPY.friendRequest.VN('Ken').body).toBe(
        'Ken muốn kết bạn với bạn',
      );
      expect(PUSH_COPY.memberJoined.VN('Trip', 'Ken').body).toBe(
        'Ken đã tham gia chuyến đi',
      );
      expect(PUSH_COPY.memberLeft.EN('Trip', 'Ken').body).toBe(
        'Ken has left the trip',
      );
    });
  });

  describe('listingStatus', () => {
    it('switches title/body on approval and locale', () => {
      expect(PUSH_COPY.listingStatus.EN('Plan', true).title).toBe(
        'Listing approved',
      );
      expect(PUSH_COPY.listingStatus.VN('Plan', false).title).toBe(
        'Tin đăng bị từ chối',
      );
    });
  });
});
