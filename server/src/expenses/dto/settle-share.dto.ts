import { ApiProperty } from '@nestjs/swagger';
import { IsBoolean } from 'class-validator';

export class SettleShareDto {
  @ApiProperty()
  @IsBoolean()
  isSettled: boolean;
}
