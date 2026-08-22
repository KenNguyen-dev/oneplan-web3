import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsNotEmpty } from 'class-validator';

export class WebhookPayloadDto {
  @ApiProperty({ description: 'Signed payload from Apple' })
  @IsString()
  @IsNotEmpty()
  signedPayload: string;
}
