import { ApiProperty } from '@nestjs/swagger';
import { IsBoolean } from 'class-validator';

export class MarkPaymentDto {
  @ApiProperty()
  @IsBoolean()
  isPaid: boolean;
}
