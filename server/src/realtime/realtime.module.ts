import { forwardRef, Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { ChatModule } from '../chat/chat.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ConnectionService } from './connection/connection.service';
import { ChatHandler } from './handlers/chat.handler';
import { FriendsHandler } from './handlers/friends.handler';
import { TripsHandler } from './handlers/trips.handler';
import { RealtimeGateway } from './realtime.gateway';

@Module({
  imports: [AuthModule, NotificationsModule, forwardRef(() => ChatModule)],
  providers: [
    ConnectionService,
    RealtimeGateway,
    ChatHandler,
    FriendsHandler,
    TripsHandler,
  ],
  exports: [ConnectionService, ChatHandler, FriendsHandler, TripsHandler],
})
export class RealtimeModule {}
