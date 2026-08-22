import { PushPayloadBuilder } from './push-payload';

describe('PushPayloadBuilder', () => {
  it('chat truncates body to 100 chars with ellipsis', () => {
    const long = 'a'.repeat(150);
    const p = PushPayloadBuilder.chat({
      tripId: 7,
      tripName: 'Da Lat',
      senderName: 'Alice',
      content: long,
    });
    expect(p.body.length).toBe(101); // 100 + '…'
    expect(p.body.endsWith('…')).toBe(true);
    expect(p.threadId).toBe('trip-7');
    expect(p.data.tripId).toBe('7');
    expect(p.data.senderName).toBe('Alice');
  });

  it('chat short body is unchanged', () => {
    const p = PushPayloadBuilder.chat({
      tripId: 1,
      tripName: 'T',
      senderName: 'A',
      content: 'hi',
    });
    expect(p.body).toBe('hi');
  });

  it('friend_request payload', () => {
    const p = PushPayloadBuilder.friendRequest({ senderDisplayName: 'Bob' });
    expect(p.type).toBe('friend_request');
    expect(p.body).toBe('Bob wants to be your friend');
  });

  it('trip_invite carries inviteCode in data', () => {
    const p = PushPayloadBuilder.tripInvite({
      inviterDisplayName: 'C',
      tripName: 'X',
      inviteCode: 'ABC123',
    });
    expect(p.data.inviteCode).toBe('ABC123');
  });

  it('member_left has threadId and tripId', () => {
    const p = PushPayloadBuilder.memberLeft({
      tripId: 4,
      tripName: 'Y',
      leavingUserName: 'D',
    });
    expect(p.threadId).toBe('trip-4');
    expect(p.data.tripId).toBe('4');
  });

  it('plan_reminder with location appends location', () => {
    const p = PushPayloadBuilder.planReminder({
      tripId: 9,
      tripName: 'Z',
      planItem: {
        id: 22,
        title: 'Coffee',
        startTime: '09:00',
        location: 'Cafe Q',
      },
    });
    expect(p.body).toBe('Coffee at 09:00 • Cafe Q');
    expect(p.data.planItemId).toBe('22');
  });

  it('plan_reminder without location omits location segment', () => {
    const p = PushPayloadBuilder.planReminder({
      tripId: 9,
      tripName: 'Z',
      planItem: { id: 22, title: 'Coffee', startTime: '09:00', location: null },
    });
    expect(p.body).toBe('Coffee at 09:00');
  });

  it('engagement carries the specific subtype as `type`, not a generic bucket', () => {
    const p = PushPayloadBuilder.engagement({
      title: 'Your next trip awaits',
      body: 'Come back!',
      deepLink: { type: 'engagement_dormant' },
    });
    expect(p.type).toBe('engagement_dormant');
  });

  it('engagement does not duplicate `type` inside data (FCM reserved-key clobber guard)', () => {
    const p = PushPayloadBuilder.engagement({
      title: 'New plan available',
      body: 'Take a look',
      deepLink: { type: 'engagement_new_plan', listingId: 7 },
    });
    expect(p.data.type).toBeUndefined();
    expect(p.data.listingId).toBe('7');
  });

  it('engagement omits tripId/listingId from data when absent', () => {
    const p = PushPayloadBuilder.engagement({
      title: 'Your next trip awaits',
      body: 'Come back!',
      deepLink: { type: 'engagement_dormant' },
    });
    expect(p.data.tripId).toBeUndefined();
    expect(p.data.listingId).toBeUndefined();
  });
});
