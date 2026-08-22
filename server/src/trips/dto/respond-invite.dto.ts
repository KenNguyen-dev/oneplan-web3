import { ApiProperty } from '@nestjs/swagger';
import { IsIn } from 'class-validator';
import { InviteStatus } from '@prisma/client';

export class RespondInviteDto {
  @ApiProperty({
    enum: ['ACCEPTED', 'DECLINED'],
    description: 'Accept or decline the invitation',
  })
  @IsIn(['ACCEPTED', 'DECLINED'])
  status: Extract<InviteStatus, 'ACCEPTED' | 'DECLINED'>;
}
