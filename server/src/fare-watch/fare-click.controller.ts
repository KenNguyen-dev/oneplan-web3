import { Controller, Get, NotFoundException, Param, Res } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { FastifyReply } from 'fastify';
import { Public } from '../auth/decorators/public.decorator';
import { PrismaService } from '../prisma/prisma.service';

// /f/:alertId - the link behind every button in a fare-alert ZNS message.
// Records the click (the engine's key engagement metric) and forwards to the
// affiliate booking page. Kept at the root path so the URL inside the Zalo
// message stays short.
@ApiExcludeController()
@Controller('f')
export class FareClickController {
  constructor(private readonly prisma: PrismaService) {}

  @Public()
  @Get(':alertId')
  async click(
    @Param('alertId') alertId: string,
    @Res() res: FastifyReply,
  ): Promise<void> {
    const id = parseInt(alertId, 10);
    if (!Number.isInteger(id)) throw new NotFoundException();
    const log = await this.prisma.fareAlertLog.findUnique({
      where: { id },
      include: { quote: true, order: true },
    });
    if (!log) throw new NotFoundException();
    // First click wins the timestamp; later clicks still redirect.
    if (!log.clickedAt) {
      await this.prisma.fareAlertLog.update({
        where: { id },
        data: { clickedAt: new Date() },
      });
    }
    const fallback = `https://www.oneplan.space/radar/?o=${log.order.publicId}`;
    await res.status(302).redirect(log.quote?.deepLink ?? fallback);
  }
}
