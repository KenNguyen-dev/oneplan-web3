import { Currency } from '@prisma/client';
import { CurrenciesController } from './currencies.controller';

describe('CurrenciesController', () => {
  let controller: CurrenciesController;

  beforeEach(() => {
    controller = new CurrenciesController();
  });

  it('returns supported currencies with server-owned display metadata', () => {
    const currencies = controller.findAll();

    expect(currencies).toEqual(
      expect.arrayContaining([
        {
          code: Currency.VND,
          name: 'Vietnamese Dong',
          symbol: 'đ',
          decimalPlaces: 0,
        },
        {
          code: Currency.USD,
          name: 'US Dollar',
          symbol: '$',
          decimalPlaces: 2,
        },
      ]),
    );

    for (const currency of currencies) {
      expect(Object.values(Currency)).toContain(currency.code);
      expect(currency.name).toEqual(expect.any(String));
      expect(currency.symbol).toEqual(expect.any(String));
      expect(currency.decimalPlaces).toEqual(expect.any(Number));
    }
  });
});
