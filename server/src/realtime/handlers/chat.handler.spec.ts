import { ChatMessageType } from '@prisma/client';
import { ChatHandler } from './chat.handler';

describe('ChatHandler', () => {
  let handler: ChatHandler;
  let connectionService: {
    getClientAuth: jest.Mock;
    sendEvent: jest.Mock;
    broadcastToRoom: jest.Mock;
    getRoomClients: jest.Mock;
    sendToUsers: jest.Mock;
    getOnlineUserIds: jest.Mock;
  };
  let chatService: {
    sendMessage: jest.Mock;
    listAcceptedMemberUserIds: jest.Mock;
  };
  let notificationsService: {
    sendChatPush: jest.Mock;
  };

  beforeEach(() => {
    connectionService = {
      getClientAuth: jest.fn(),
      sendEvent: jest.fn(),
      broadcastToRoom: jest.fn(),
      getRoomClients: jest.fn(),
      sendToUsers: jest.fn(),
      getOnlineUserIds: jest.fn(),
    };

    chatService = {
      sendMessage: jest.fn(),
      listAcceptedMemberUserIds: jest.fn(),
    };

    notificationsService = {
      sendChatPush: jest.fn(),
    };

    handler = new ChatHandler(
      connectionService as never,
      chatService as never,
      notificationsService as never,
    );
  });

  it('fans out new messages to room members and other member sockets', async () => {
    const client = {} as never;
    const roomClients = new Set([client]);
    const messageDto = {
      id: 99,
      tripId: 7,
      senderId: 11,
      senderDisplayName: 'Ken',
      senderAvatarUrl: null,
      content: 'hello',
      type: ChatMessageType.TEXT,
      imageUrl: null,
      createdAt: '2026-04-12T00:00:00.000Z',
    };

    connectionService.getClientAuth.mockReturnValue({ userId: 11 });
    chatService.sendMessage.mockResolvedValue(messageDto);
    chatService.listAcceptedMemberUserIds.mockResolvedValue([11, 12, 13]);
    connectionService.getRoomClients.mockReturnValue(roomClients);
    connectionService.getOnlineUserIds.mockReturnValue([11, 12]);

    await handler.handleSendMessage(client, {
      tripId: 7,
      type: 'TEXT',
      content: 'hello',
    });

    expect(connectionService.broadcastToRoom).toHaveBeenCalledWith(
      7,
      'newMessage',
      messageDto,
    );
    expect(chatService.listAcceptedMemberUserIds).toHaveBeenCalledWith(7);
    expect(connectionService.sendToUsers).toHaveBeenCalledWith(
      [11, 12, 13],
      'newMessage',
      messageDto,
      roomClients,
    );
    expect(notificationsService.sendChatPush).toHaveBeenCalledWith(
      7,
      11,
      'Ken',
      'hello',
      [11, 12],
    );
  });
});
