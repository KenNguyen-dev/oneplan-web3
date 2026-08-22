import { BadRequestException, Controller, Get, Query } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOkResponse,
  ApiOperation,
  ApiQuery,
  ApiTags,
} from '@nestjs/swagger';
import { Currency } from '@prisma/client';
import { ExchangeRateResponseDto } from './dto/exchange-rate-response.dto';
import { ExchangeRatesService } from './exchange-rates.service';

const VALID_CURRENCIES = new Set<string>(Object.values(Currency));

@ApiBearerAuth()
@ApiTags('Exchange Rates')
@Controller('exchange-rates')
export class ExchangeRatesController {
  constructor(private readonly exchangeRatesService: ExchangeRatesService) {}

  @Get()
  @ApiOperation({
    operationId: 'getExchangeRate',
    summary: 'Get the current exchange rate between two supported currencies.',
  })
  @ApiQuery({ name: 'from', enum: Currency, enumName: 'Currency' })
  @ApiQuery({ name: 'to', enum: Currency, enumName: 'Currency' })
  @ApiOkResponse({ type: ExchangeRateResponseDto })
  async getRate(
    @Query('from') from: string,
    @Query('to') to: string,
  ): Promise<ExchangeRateResponseDto> {
    if (!from || !VALID_CURRENCIES.has(from)) {
      throw new BadRequestException(
        `Invalid 'from' currency. Must be one of: ${Object.values(Currency).join(', ')}`,
      );
    }
    if (!to || !VALID_CURRENCIES.has(to)) {
      throw new BadRequestException(
        `Invalid 'to' currency. Must be one of: ${Object.values(Currency).join(', ')}`,
      );
    }

    const result = await this.exchangeRatesService.getRate(
      from as Currency,
      to as Currency,
    );

    return {
      from: from as Currency,
      to: to as Currency,
      rate: Number(result.rate.toString()),
      fetchedAt: result.fetchedAt.toISOString(),
      isStale: result.isStale,
    };
  }
}
