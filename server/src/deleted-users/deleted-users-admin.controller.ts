import { Controller, Get, Param, ParseIntPipe } from '@nestjs/common';
import {
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { AdminOnly } from '../auth/decorators/admin-only.decorator';
import {
  DeletedUserArchiveDto,
  DeletedUserSummaryDto,
} from './dto/deleted-user.dto';
import {
  DELETED_USER_RETENTION_DAYS,
  DeletedUsersService,
} from './deleted-users.service';

@ApiTags('Deleted Users Admin')
@Controller('deleted-users/admin')
export class DeletedUsersAdminController {
  constructor(private readonly deletedUsers: DeletedUsersService) {}

  @Get()
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminListDeletedUsers',
    summary: `Accounts deleted in the last ${DELETED_USER_RETENTION_DAYS} days, newest first. Archives are purged automatically after that.`,
  })
  @ApiOkResponse({ type: [DeletedUserSummaryDto] })
  list(): Promise<DeletedUserSummaryDto[]> {
    return this.deletedUsers.list();
  }

  @Get(':id')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGetDeletedUser',
    summary: 'Full snapshot of a deleted account.',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: DeletedUserArchiveDto })
  @ApiNotFoundResponse({ description: 'Archive not found or already purged' })
  get(@Param('id', ParseIntPipe) id: number): Promise<DeletedUserArchiveDto> {
    return this.deletedUsers.get(id);
  }
}
