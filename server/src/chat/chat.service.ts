import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ChatMessageType, InviteStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { ChatMessageDto } from './dto/chat-message.dto';
import { ChatMessageListDto } from './dto/chat-message-list.dto';

const DEFAULT_TAKE = 30;

const MESSAGE_INCLUDE = {
  sender: {
    select: { id: true, displayName: true, avatarUrl: true },
  },
} as const;

type MessageWithSender = {
  id: number;
  tripId: number;
  senderId: number | null;
  content: string;
  type: ChatMessageType;
  imageObjectKey: string | null;
  createdAt: Date;
  sender: { id: number; displayName: string; avatarUrl: string | null } | null;
};

type SendMessageInput = {
  content: string;
  type: ChatMessageType;
  imageObjectKey?: string | null;
};

@Injectable()
export class ChatService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storageService: StorageService,
  ) {}

  async listMessages(
    tripId: number,
    userId: number,
    cursor?: number,
    take?: number,
  ): Promise<ChatMessageListDto> {
    await this.assertAcceptedMember(tripId, userId);

    const limit = take ?? DEFAULT_TAKE;

    const messages = await this.prisma.chatMessage.findMany({
      where: { tripId },
      include: MESSAGE_INCLUDE,
      orderBy: { id: 'desc' },
      take: limit + 1,
      ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}),
    });

    const hasMore = messages.length > limit;
    const results = hasMore ? messages.slice(0, limit) : messages;
    const nextCursor = hasMore ? results[results.length - 1].id : null;

    return {
      data: await Promise.all(results.map((m) => this.formatMessage(m))),
      nextCursor,
    };
  }

  async sendMessage(
    tripId: number,
    senderId: number,
    input: SendMessageInput,
  ): Promise<ChatMessageDto> {
    await this.assertAcceptedMember(tripId, senderId);

    const message = await this.prisma.chatMessage.create({
      data: {
        tripId,
        senderId,
        content: input.content.trim(),
        type: input.type,
        imageObjectKey:
          input.type === ChatMessageType.IMAGE
            ? (input.imageObjectKey ?? null)
            : null,
      },
      include: MESSAGE_INCLUDE,
    });

    return await this.formatMessage(message);
  }

  async markMessagesSeen(
    tripId: number,
    userId: number,
    messageId: number,
  ): Promise<void> {
    await this.assertAcceptedMember(tripId, userId);

    const message = await this.prisma.chatMessage.findUnique({
      where: { id: messageId },
      select: { id: true, tripId: true },
    });

    if (!message || message.tripId !== tripId) {
      throw new NotFoundException('Message not found in this trip');
    }

    await this.prisma.tripMember.updateMany({
      where: {
        tripId,
        userId,
        inviteStatus: InviteStatus.ACCEPTED,
        OR: [
          { lastSeenChatMessageId: null },
          { lastSeenChatMessageId: { lt: messageId } },
        ],
      },
      data: { lastSeenChatMessageId: messageId },
    });
  }

  async listAcceptedMemberUserIds(tripId: number): Promise<number[]> {
    const members = await this.prisma.tripMember.findMany({
      where: {
        tripId,
        inviteStatus: InviteStatus.ACCEPTED,
      },
      select: { userId: true },
    });

    return members.map((member) => member.userId);
  }

  async assertAcceptedMember(tripId: number, userId: number): Promise<void> {
    const member = await this.prisma.tripMember.findUnique({
      where: { tripId_userId: { tripId, userId } },
    });

    if (!member || member.inviteStatus !== InviteStatus.ACCEPTED) {
      throw new ForbiddenException('You are not a member of this trip');
    }
  }

  private async formatMessage(
    message: MessageWithSender,
  ): Promise<ChatMessageDto> {
    return {
      id: message.id,
      tripId: message.tripId,
      senderId: message.sender?.id ?? null,
      senderDisplayName: message.sender?.displayName ?? 'Deleted User',
      senderAvatarUrl: message.sender
        ? await this.resolveMediaUrlOrPassThrough(message.sender.avatarUrl)
        : null,
      content: message.content,
      type: message.type,
      imageUrl: await this.resolveMediaUrlOrPassThrough(message.imageObjectKey),
      createdAt: message.createdAt.toISOString(),
    };
  }

  private async resolveMediaUrlOrPassThrough(
    value: string | null,
  ): Promise<string | null> {
    if (!value) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    try {
      const { url } = await this.storageService.getSignedThumbUrl(value);
      return url;
    } catch {
      return value;
    }
  }
}
