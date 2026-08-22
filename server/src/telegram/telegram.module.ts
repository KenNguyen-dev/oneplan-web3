import { Module } from '@nestjs/common';
import { AdminGuard } from '../auth/guards/admin.guard';
import { TelegramController } from './telegram.controller';
import { TelegramBotService } from './telegram-bot.service';
import { TelegramCodeService } from './telegram-code.service';
import { TelegramSettingsService } from './telegram-settings.service';
import { TelegramWelcomeService } from './telegram-welcome.service';

@Module({
  controllers: [TelegramController],
  providers: [
    TelegramCodeService,
    TelegramSettingsService,
    TelegramWelcomeService,
    TelegramBotService,
    AdminGuard,
  ],
  exports: [TelegramCodeService],
})
export class TelegramModule {}
