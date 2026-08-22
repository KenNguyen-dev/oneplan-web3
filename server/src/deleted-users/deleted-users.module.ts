import { Module } from '@nestjs/common';
import { AdminGuard } from '../auth/guards/admin.guard';
import { DeletedUsersAdminController } from './deleted-users-admin.controller';
import { DeletedUsersService } from './deleted-users.service';

// Keeps a read-only snapshot of deleted accounts for a bounded retention window
// and exposes it to admins. AuthModule imports this to archive inside the
// account-delete transaction. PrismaModule and ScheduleModule are global.
@Module({
  controllers: [DeletedUsersAdminController],
  providers: [DeletedUsersService, AdminGuard],
  exports: [DeletedUsersService],
})
export class DeletedUsersModule {}
