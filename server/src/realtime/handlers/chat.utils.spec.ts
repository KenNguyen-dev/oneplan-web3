import { ChatMessageType } from '@prisma/client';
import { parseSendMessagePayload } from './chat.utils';

describe('ChatHandler sendMessage payload parsing', () => {
  it('supports backward-compatible text payloads without explicit type', () => {
    const parsed = parseSendMessagePayload({
      tripId: 8,
      content: ' hello ',
    });

    expect(parsed).toEqual({
      value: {
        tripId: 8,
        type: ChatMessageType.TEXT,
        content: 'hello',
        imageObjectKey: null,
      },
    });
  });

  it('parses image payload with matching trip photo prefix', () => {
    const parsed = parseSendMessagePayload({
      tripId: 8,
      type: 'IMAGE',
      imageObjectKey: 'trips/8/photos/abc.jpg',
    });

    expect(parsed).toEqual({
      value: {
        tripId: 8,
        type: ChatMessageType.IMAGE,
        content: '',
        imageObjectKey: 'trips/8/photos/abc.jpg',
      },
    });
  });

  it('rejects image payload when object key is for another trip', () => {
    const parsed = parseSendMessagePayload({
      tripId: 8,
      type: 'IMAGE',
      imageObjectKey: 'trips/99/photos/abc.jpg',
    });

    expect(parsed).toEqual({
      error: 'imageObjectKey does not match this trip photo path',
    });
  });
});
