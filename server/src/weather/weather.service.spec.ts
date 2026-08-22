import { ConfigService } from '@nestjs/config';
import { WeatherService } from './weather.service';
import { PrismaService } from '../prisma/prisma.service';

describe('WeatherService.classify', () => {
  let service: WeatherService;

  beforeEach(() => {
    const config = {
      get: (key: string) => {
        if (key === 'WEATHER_HOT_C') return 33;
        if (key === 'WEATHER_COLD_C') return 12;
        return undefined;
      },
    } as unknown as ConfigService;
    service = new WeatherService({} as PrismaService, config);
  });

  it('maps thunderstorms to STORM regardless of temp', () => {
    expect(service.classify('THUNDERSTORM', 28)).toBe('STORM');
    expect(service.classify('HEAVY_THUNDERSTORM', 35)).toBe('STORM');
    expect(service.classify('HAIL', 20)).toBe('STORM');
  });

  it('maps rain/showers to RAIN', () => {
    expect(service.classify('RAIN', 26)).toBe('RAIN');
    expect(service.classify('LIGHT_RAIN_SHOWERS', 30)).toBe('RAIN');
    expect(service.classify('HEAVY_RAIN', 24)).toBe('RAIN');
  });

  it('hot clear weather is HOT', () => {
    expect(service.classify('CLEAR', 34)).toBe('HOT');
    expect(service.classify('MOSTLY_CLEAR', 33)).toBe('HOT');
  });

  it('cold weather is COLD; snow is COLD', () => {
    expect(service.classify('CLEAR', 8)).toBe('COLD');
    expect(service.classify('LIGHT_SNOW', 2)).toBe('COLD');
  });

  it('pleasant weather is MILD (no trigger)', () => {
    expect(service.classify('PARTLY_CLOUDY', 24)).toBe('MILD');
    expect(service.classify('CLOUDY', 20)).toBe('MILD');
  });
});
