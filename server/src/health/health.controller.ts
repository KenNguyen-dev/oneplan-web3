import { Controller, Get } from '@nestjs/common';
import { ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../auth/decorators/public.decorator';
import { HealthService } from './health.service';
import { LiveResponseDto, ReadyResponseDto } from './dto/health.dto';

@Public()
@ApiTags('Health')
@Controller('health')
export class HealthController {
  constructor(private readonly healthService: HealthService) {}

  @Get('live')
  @ApiOperation({ operationId: 'checkLiveness', summary: 'Liveness probe' })
  @ApiOkResponse({ type: LiveResponseDto })
  live(): LiveResponseDto {
    return this.healthService.live();
  }

  @Get('ready')
  @ApiOperation({
    operationId: 'checkReadiness',
    summary: 'Readiness probe (includes database check)',
  })
  @ApiOkResponse({ type: ReadyResponseDto })
  ready(): Promise<ReadyResponseDto> {
    return this.healthService.ready();
  }
}
