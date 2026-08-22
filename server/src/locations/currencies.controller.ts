import { Controller, Get } from '@nestjs/common';
import { ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Currency } from '@prisma/client';
import { Public } from '../auth/decorators/public.decorator';
import { CurrencyDto } from './dto/currency.dto';

const CURRENCIES: CurrencyDto[] = [
  {
    code: Currency.VND,
    name: 'Vietnamese Dong',
    symbol: 'đ',
    decimalPlaces: 0,
  },
  { code: Currency.USD, name: 'US Dollar', symbol: '$', decimalPlaces: 2 },
  { code: Currency.EUR, name: 'Euro', symbol: '€', decimalPlaces: 2 },
  { code: Currency.THB, name: 'Thai Baht', symbol: '฿', decimalPlaces: 2 },
  {
    code: Currency.KRW,
    name: 'South Korean Won',
    symbol: '₩',
    decimalPlaces: 0,
  },
  { code: Currency.JPY, name: 'Japanese Yen', symbol: '¥', decimalPlaces: 0 },
  { code: Currency.CNY, name: 'Chinese Yuan', symbol: '¥', decimalPlaces: 2 },
  {
    code: Currency.TWD,
    name: 'New Taiwan Dollar',
    symbol: 'NT$',
    decimalPlaces: 0,
  },
  {
    code: Currency.SGD,
    name: 'Singapore Dollar',
    symbol: 'S$',
    decimalPlaces: 2,
  },
  {
    code: Currency.MYR,
    name: 'Malaysian Ringgit',
    symbol: 'RM',
    decimalPlaces: 2,
  },
];

@Public()
@ApiTags('Currencies')
@Controller('currencies')
export class CurrenciesController {
  @Get()
  @ApiOperation({
    operationId: 'listCurrencies',
    summary: 'List all supported currencies',
  })
  @ApiOkResponse({ type: [CurrencyDto] })
  findAll(): CurrencyDto[] {
    return CURRENCIES;
  }
}
