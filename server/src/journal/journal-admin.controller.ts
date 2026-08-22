import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import {
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { JournalStatus } from '@prisma/client';
import { AdminOnly } from '../auth/decorators/admin-only.decorator';
import { JournalService } from './journal.service';
import { CreateJournalDto } from './dto/create-journal.dto';
import { UpdateJournalDto } from './dto/update-journal.dto';
import { ListJournalsQueryDto } from './dto/list-journals-query.dto';
import { JournalDto } from './dto/journal.dto';

@ApiTags('Journal Admin')
@Controller('journal/admin')
export class JournalAdminController {
  constructor(private readonly journalService: JournalService) {}

  @Get('journals')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminListJournals',
    summary: 'List journal posts, filterable by status and label.',
  })
  @ApiOkResponse({ type: [JournalDto] })
  list(@Query() query: ListJournalsQueryDto): Promise<JournalDto[]> {
    return this.journalService.adminList(query);
  }

  @Get('journals/:id')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGetJournal',
    summary: 'Fetch a single journal post.',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: JournalDto })
  @ApiNotFoundResponse({ description: 'Journal not found' })
  get(@Param('id', ParseIntPipe) id: number): Promise<JournalDto> {
    return this.journalService.adminGet(id);
  }

  @Post('journals')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminCreateJournal',
    summary: 'Create a journal post (starts as a DRAFT).',
  })
  @ApiOkResponse({ type: JournalDto })
  create(@Body() dto: CreateJournalDto): Promise<JournalDto> {
    return this.journalService.adminCreate(dto);
  }

  @Patch('journals/:id')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminUpdateJournal',
    summary: 'Update a journal post.',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: JournalDto })
  @ApiNotFoundResponse({ description: 'Journal not found' })
  update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateJournalDto,
  ): Promise<JournalDto> {
    return this.journalService.adminUpdate(id, dto);
  }

  @Post('journals/:id/publish')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminPublishJournal',
    summary: 'Publish a journal post (status=PUBLISHED).',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: JournalDto })
  @ApiNotFoundResponse({ description: 'Journal not found' })
  publish(@Param('id', ParseIntPipe) id: number): Promise<JournalDto> {
    return this.journalService.adminSetStatus(id, JournalStatus.PUBLISHED);
  }

  @Post('journals/:id/unpublish')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminUnpublishJournal',
    summary: 'Move a journal post back to DRAFT (status=DRAFT).',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: JournalDto })
  @ApiNotFoundResponse({ description: 'Journal not found' })
  unpublish(@Param('id', ParseIntPipe) id: number): Promise<JournalDto> {
    return this.journalService.adminSetStatus(id, JournalStatus.DRAFT);
  }

  @Delete('journals/:id')
  @AdminOnly()
  @HttpCode(204)
  @ApiOperation({
    operationId: 'adminDeleteJournal',
    summary: 'Delete a journal post and its cover image.',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiNoContentResponse({ description: 'Journal deleted' })
  @ApiNotFoundResponse({ description: 'Journal not found' })
  remove(@Param('id', ParseIntPipe) id: number): Promise<void> {
    return this.journalService.adminDelete(id);
  }
}
