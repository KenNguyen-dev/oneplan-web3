import { ApiProperty } from '@nestjs/swagger';
import { TripMemberRole } from '@prisma/client';
import { IsEnum } from 'class-validator';

export class SetMemberRoleDto {
  @ApiProperty({
    enum: TripMemberRole,
    enumName: 'TripMemberRole',
    description:
      'CO_HOST or MEMBER. HOST is not assignable: it belongs to whoever ' +
      'created the trip.',
  })
  @IsEnum(TripMemberRole)
  role: TripMemberRole;
}
