import { ChatMessageType } from '@prisma/client';

export type SendMessagePayload = {
  tripId: number;
  type: ChatMessageType;
  content: string;
  imageObjectKey: string | null;
};

export type ParsedSendMessagePayload =
  | { value: SendMessagePayload }
  | { error: string };

export function normalizeMessageType(
  value: unknown,
): ChatMessageType | undefined | null {
  if (value === undefined || value === null || value === '') {
    return undefined;
  }
  if (typeof value !== 'string') {
    return null;
  }
  const normalized = value.trim().toUpperCase();
  if (normalized === ChatMessageType.TEXT) {
    return ChatMessageType.TEXT;
  }
  if (normalized === ChatMessageType.IMAGE) {
    return ChatMessageType.IMAGE;
  }
  return null;
}

export function toPositiveInt(value: unknown): number | null {
  if (typeof value === 'number' && Number.isInteger(value) && value > 0) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isInteger(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return null;
}

export function parseSendMessagePayload(
  data: Record<string, unknown>,
): ParsedSendMessagePayload {
  const tripId = toPositiveInt(data.tripId);
  if (!tripId) {
    return { error: 'tripId is required' };
  }

  const normalizedType = normalizeMessageType(data.type);
  if (normalizedType === null) {
    return { error: 'Message type must be either TEXT or IMAGE' };
  }

  const rawContent = typeof data.content === 'string' ? data.content : '';
  const trimmedContent = rawContent.trim();
  const rawImageObjectKey =
    typeof data.imageObjectKey === 'string' ? data.imageObjectKey.trim() : '';

  const type: ChatMessageType =
    normalizedType ??
    (rawImageObjectKey.length > 0
      ? ChatMessageType.IMAGE
      : ChatMessageType.TEXT);

  if (trimmedContent.length > 2000) {
    return { error: 'Message content must be at most 2000 characters' };
  }

  if (type === ChatMessageType.TEXT) {
    if (trimmedContent.length === 0) {
      return { error: 'Message content is required' };
    }

    return {
      value: {
        tripId,
        type,
        content: trimmedContent,
        imageObjectKey: null,
      },
    };
  }

  if (rawImageObjectKey.length === 0) {
    return { error: 'imageObjectKey is required for image messages' };
  }

  const expectedPrefix = `trips/${tripId}/photos/`;
  if (!rawImageObjectKey.startsWith(expectedPrefix)) {
    return { error: 'imageObjectKey does not match this trip photo path' };
  }

  return {
    value: {
      tripId,
      type,
      content: trimmedContent,
      imageObjectKey: rawImageObjectKey,
    },
  };
}
