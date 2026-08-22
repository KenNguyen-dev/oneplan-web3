import { ApiProperty } from '@nestjs/swagger';

export class DeletedUserSummaryDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({
    type: 'integer',
    description: 'The id the user had before deletion',
  })
  originalUserId: number;

  @ApiProperty()
  email: string;

  @ApiProperty()
  displayName: string;

  @ApiProperty({ description: 'When the user deleted their account (ISO)' })
  deletedAt: string;

  @ApiProperty({
    description: 'When this archive is automatically purged (ISO)',
  })
  purgeAt: string;

  @ApiProperty({
    type: 'integer',
    description: 'Days left before the archive is purged',
  })
  daysLeft: number;
}

export class DeletedUserArchiveDto extends DeletedUserSummaryDto {
  @ApiProperty({
    type: 'object',
    additionalProperties: true,
    description:
      'Full snapshot taken at deletion: profile, subscription, auth providers, trips, expenses, listings, scan credits, gifts and an activity summary.',
  })
  snapshot: unknown;
}
