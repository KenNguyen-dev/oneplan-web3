import { Module } from '@nestjs/common';
import { PrismaModule } from '../../prisma/prisma.module';
import { ZnsService } from './zns.service';

@Module({
  imports: [PrismaModule],
  providers: [ZnsService],
  exports: [ZnsService],
})
export class ZaloModule {}
