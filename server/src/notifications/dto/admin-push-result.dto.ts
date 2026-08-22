import { ApiProperty } from '@nestjs/swagger';

export class AdminPushResultDto {
  @ApiProperty({
    type: 'integer',
    description: 'Number of device tokens the push was dispatched to.',
  })
  recipientDevices: number;

  @ApiProperty({ type: 'integer', description: 'Tokens APNs accepted.' })
  sent: number;

  @ApiProperty({ type: 'integer', description: 'Tokens APNs rejected.' })
  failed: number;

  @ApiProperty({
    type: [String],
    description:
      'Targeted recipients (emails / user IDs) that matched no user. Empty for broadcasts.',
  })
  unknownRecipients: string[];
}
