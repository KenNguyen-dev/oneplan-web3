import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsObject, IsString } from 'class-validator';

export class PlayWebhookPayloadDto {
  @ApiProperty({ description: 'The Pub/Sub message data' })
  @IsObject()
  @IsNotEmpty()
  message: {
    data: string; // base64 encoded DeveloperNotification
    messageId: string;
    publishTime: string;
  };

  @ApiProperty({ description: 'The Pub/Sub subscription name' })
  @IsString()
  @IsNotEmpty()
  subscription: string;
}
