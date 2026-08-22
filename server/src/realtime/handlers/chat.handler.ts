import { forwardRef, Inject, Injectable } from '@nestjs/common';
import { ChatMessageType } from '@prisma/client';
import { WebSocket } from 'ws';
import { ChatService } from '../../chat/chat.service';
import { NotificationsService } from '../../notifications/notifications.service';
import { REALTIME_EVENTS } from '../constants';
import { ConnectionService } from '../connection/connection.service';
import { parseSendMessagePayload } from './chat.utils';

@Injectable()
export class ChatHandler {
  constructor(
    private readonly connectionService: ConnectionService,
    @Inject(forwardRef(() => ChatService))
    private readonly chatService: ChatService,
    private readonly notificationsService: NotificationsService,
  ) {}

  async handleJoinTrip(
    client: WebSocket,
    data: { tripId: number },
  ): Promise<void> {
    try {
      const auth = this.connectionService.getClientAuth(client);
      if (!auth) {
        this.connectionService.sendEvent(client, REALTIME_EVENTS.ERROR, {
          message: 'Not authenticated',
        });
        return;
      }
      await this.chatService.assertAcceptedMember(data.tripId, auth.userId);
      this.connectionService.joinRoom(data.tripId, client);
    } catch {
      this.connectionService.sendEvent(client, REALTIME_EVENTS.ERROR, {
        message: 'Not a member of this trip',
      });
    }
  }

  handleLeaveTrip(client: WebSocket, data: { tripId: number }): void {
    this.connectionService.leaveRoom(data.tripId, client);
  }

  async handleSendMessage(
    client: WebSocket,
    data: Record<string, unknown> | undefined,
  ): Promise<void> {
    try {
      const auth = this.connectionService.getClientAuth(client);
      if (!auth) {
        this.connectionService.sendEvent(client, REALTIME_EVENTS.ERROR, {
          message: 'Not authenticated',
        });
        return;
      }

      const parsed = parseSendMessagePayload(data ?? {});
      if ('error' in parsed) {
        this.connectionService.sendEvent(client, REALTIME_EVENTS.ERROR, {
          message: parsed.error,
        });
        return;
      }
      const payload = parsed.value;

      const messageDto = await this.chatService.sendMessage(
        payload.tripId,
        auth.userId,
        {
          content: payload.content,
          type: payload.type,
          imageObjectKey: payload.imageObjectKey,
        },
      );

      this.connectionService.broadcastToRoom(
        payload.tripId,
        REALTIME_EVENTS.NEW_MESSAGE,
        messageDto,
      );

      const memberUserIds = await this.chatService.listAcceptedMemberUserIds(
        payload.tripId,
      );
      const roomClients = this.connectionService.getRoomClients(payload.tripId);
      this.connectionService.sendToUsers(
        memberUserIds,
        REALTIME_EVENTS.NEW_MESSAGE,
        messageDto,
        roomClients,
      );

      const onlineUserIds = this.connectionService.getOnlineUserIds(
        payload.tripId,
      );
      const pushBody =
        messageDto.type === ChatMessageType.IMAGE
          ? 'Sent a photo'
          : messageDto.content;
      void this.notificationsService.sendChatPush(
        payload.tripId,
        auth.userId,
        messageDto.senderDisplayName,
        pushBody,
        onlineUserIds,
      );
    } catch {
      this.connectionService.sendEvent(client, REALTIME_EVENTS.ERROR, {
        message: 'Failed to send message',
      });
    }
  }
}
