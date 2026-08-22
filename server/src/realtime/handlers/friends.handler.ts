import { Injectable } from '@nestjs/common';
import { FriendRequestDto } from '../../friends/dto/friend-request.dto';
import { REALTIME_EVENTS } from '../constants';
import { ConnectionService } from '../connection/connection.service';

@Injectable()
export class FriendsHandler {
  constructor(private readonly connectionService: ConnectionService) {}

  sendFriendRequest(userId: number, payload: FriendRequestDto): void {
    this.connectionService.sendToUser(
      userId,
      REALTIME_EVENTS.FRIEND_REQUEST_RECEIVED,
      payload,
    );
  }

  sendFriendRequestAccepted(
    userId: number,
    data: { acceptedBy: string },
  ): void {
    this.connectionService.sendToUser(
      userId,
      REALTIME_EVENTS.FRIEND_REQUEST_ACCEPTED,
      data,
    );
  }
}
