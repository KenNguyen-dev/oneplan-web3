import { Module } from '@nestjs/common';
import { JournalAdminController } from './journal-admin.controller';
import { JournalService } from './journal.service';
import { AdminGuard } from '../auth/guards/admin.guard';
import { StorageModule } from '../storage/storage.module';

@Module({
  imports: [StorageModule],
  controllers: [JournalAdminController],
  providers: [JournalService, AdminGuard],
  exports: [JournalService],
})
export class JournalModule {}
