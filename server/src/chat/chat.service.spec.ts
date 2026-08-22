import { ChatMessageType, InviteStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { ChatService } from './chat.service';

describe('ChatService', () => {
  let service: ChatService;
  let prisma: Pick<PrismaService, 'tripMember' | 'chatMessage'>;
  let storageService: Pick<StorageService, 'getSignedThumbUrl'>;

  beforeEach(() => {
    prisma = {
      tripMember: {
        findUnique: jest.fn().mockResolvedValue({
          tripId: 1,
          userId: 11,
          inviteStatus: InviteStatus.ACCEPTED,
        }),
        updateMany: jest.fn(),
      },
      chatMessage: {
        create: jest.fn(),
        findMany: jest.fn(),
        findUnique: jest.fn(),
      },
    } as unknown as Pick<PrismaService, 'tripMember' | 'chatMessage'>;

    storageService = {
      getSignedThumbUrl: jest.fn(),
    };

    service = new ChatService(
      prisma as PrismaService,
      storageService as StorageService,
    );
  });

  it('creates text message and clears image object key', async () => {
    const createdAt = new Date('2026-04-10T01:23:45.000Z');

    (prisma.chatMessage.create as jest.Mock).mockResolvedValue({
      id: 100,
      tripId: 1,
      senderId: 11,
      content: 'hello team',
      type: ChatMessageType.TEXT,
      imageObjectKey: null,
      createdAt,
      sender: {
        id: 11,
        displayName: 'Ken',
        avatarUrl: null,
      },
    });

    const result = await service.sendMessage(1, 11, {
      content: ' hello team ',
      type: ChatMessageType.TEXT,
      imageObjectKey: 'trips/1/photos/ignored.jpg',
    });

    // eslint-disable-next-line @typescript-eslint/unbound-method
    expect(prisma.chatMessage.create as jest.Mock).toHaveBeenCalledWith({
      data: {
        tripId: 1,
        senderId: 11,
        content: 'hello team',
        type: ChatMessageType.TEXT,
        imageObjectKey: null,
      },
      include: {
        sender: {
          select: { id: true, displayName: true, avatarUrl: true },
        },
      },
    });

    expect(result).toEqual({
      id: 100,
      tripId: 1,
      senderId: 11,
      senderDisplayName: 'Ken',
      senderAvatarUrl: null,
      content: 'hello team',
      type: ChatMessageType.TEXT,
      imageUrl: null,
      createdAt: '2026-04-10T01:23:45.000Z',
    });
  });

  it('creates image message and resolves signed image URL', async () => {
    const createdAt = new Date('2026-04-10T02:00:00.000Z');
    const imageObjectKey = 'trips/1/photos/abc.jpg';
    const avatarObjectKey = 'users/11/avatar/avatar.jpg';

    (prisma.chatMessage.create as jest.Mock).mockResolvedValue({
      id: 101,
      tripId: 1,
      senderId: 11,
      content: '',
      type: ChatMessageType.IMAGE,
      imageObjectKey,
      createdAt,
      sender: {
        id: 11,
        displayName: 'Ken',
        avatarUrl: avatarObjectKey,
      },
    });
    (storageService.getSignedThumbUrl as jest.Mock)
      .mockResolvedValueOnce({
        url: 'https://signed.example.com/avatar',
      })
      .mockResolvedValueOnce({
        url: 'https://signed.example.com/image',
      });

    const result = await service.sendMessage(1, 11, {
      content: '',
      type: ChatMessageType.IMAGE,
      imageObjectKey,
    });

    expect(storageService.getSignedThumbUrl).toHaveBeenNthCalledWith(
      1,
      avatarObjectKey,
    );
    expect(storageService.getSignedThumbUrl).toHaveBeenNthCalledWith(
      2,
      imageObjectKey,
    );
    expect(result.type).toBe(ChatMessageType.IMAGE);
    expect(result.senderAvatarUrl).toBe('https://signed.example.com/avatar');
    expect(result.imageUrl).toBe('https://signed.example.com/image');
  });

  it('lists mixed text/image messages with resolved image URLs', async () => {
    const createdAt = new Date('2026-04-10T03:00:00.000Z');

    (prisma.chatMessage.findMany as jest.Mock).mockResolvedValue([
      {
        id: 2,
        tripId: 1,
        senderId: 12,
        content: '',
        type: ChatMessageType.IMAGE,
        imageObjectKey: 'trips/1/photos/image.jpg',
        createdAt,
        sender: {
          id: 12,
          displayName: 'Linh',
          avatarUrl: 'users/12/avatar/linh.jpg',
        },
      },
      {
        id: 1,
        tripId: 1,
        senderId: 11,
        content: 'hi',
        type: ChatMessageType.TEXT,
        imageObjectKey: null,
        createdAt,
        sender: {
          id: 11,
          displayName: 'Ken',
          avatarUrl: null,
        },
      },
    ]);

    (storageService.getSignedThumbUrl as jest.Mock)
      .mockResolvedValueOnce({
        url: 'https://signed.example.com/avatar',
      })
      .mockResolvedValueOnce({
        url: 'https://signed.example.com/image',
      });

    const result = await service.listMessages(1, 11);

    expect(result.nextCursor).toBeNull();
    expect(result.data[0].type).toBe(ChatMessageType.IMAGE);
    expect(result.data[0].senderAvatarUrl).toBe(
      'https://signed.example.com/avatar',
    );
    expect(result.data[0].imageUrl).toBe('https://signed.example.com/image');
    expect(result.data[1].type).toBe(ChatMessageType.TEXT);
    expect(result.data[1].imageUrl).toBeNull();
  });

  it('marks messages as seen when the message belongs to the trip', async () => {
    (prisma.chatMessage.findUnique as jest.Mock).mockResolvedValue({
      id: 55,
      tripId: 1,
    });
    (prisma.tripMember.updateMany as jest.Mock).mockResolvedValue({ count: 1 });

    await service.markMessagesSeen(1, 11, 55);

    expect(prisma.tripMember.updateMany as jest.Mock).toHaveBeenCalledWith({
      where: {
        tripId: 1,
        userId: 11,
        inviteStatus: InviteStatus.ACCEPTED,
        OR: [
          { lastSeenChatMessageId: null },
          { lastSeenChatMessageId: { lt: 55 } },
        ],
      },
      data: { lastSeenChatMessageId: 55 },
    });
  });

  it('rejects markMessagesSeen when the message is from another trip', async () => {
    (prisma.chatMessage.findUnique as jest.Mock).mockResolvedValue({
      id: 55,
      tripId: 99,
    });

    await expect(service.markMessagesSeen(1, 11, 55)).rejects.toThrow(
      'Message not found in this trip',
    );
    expect(prisma.tripMember.updateMany as jest.Mock).not.toHaveBeenCalled();
  });
});
