import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Patch,
  Post,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { CreateTripNoteDto } from './dto/create-trip-note.dto';
import { TripNoteDto } from './dto/trip-note.dto';
import { TripNoteListDto } from './dto/trip-note-list.dto';
import { UpdateTripNoteDto } from './dto/update-trip-note.dto';
import { TripNotesService } from './trip-notes.service';

@ApiBearerAuth()
@ApiTags('Trip Notes')
@Controller('trips/:tripId/notes')
export class TripNotesController {
  constructor(private readonly tripNotesService: TripNotesService) {}

  @Get()
  @ApiOperation({
    operationId: 'listTripNotes',
    summary: 'List notes for a trip',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiOkResponse({ type: TripNoteListDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  listNotes(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
  ): Promise<TripNoteListDto> {
    return this.tripNotesService.listNotes(tripId, userId);
  }

  @Post()
  @ApiOperation({
    operationId: 'createTripNote',
    summary: 'Create a trip note',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiCreatedResponse({ type: TripNoteDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  createNote(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Body() dto: CreateTripNoteDto,
  ): Promise<TripNoteDto> {
    return this.tripNotesService.createNote(tripId, userId, dto);
  }

  @Patch(':id')
  @ApiOperation({
    operationId: 'updateTripNote',
    summary: 'Update a trip note',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Note ID' })
  @ApiOkResponse({ type: TripNoteDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Note not found' })
  updateNote(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateTripNoteDto,
  ): Promise<TripNoteDto> {
    return this.tripNotesService.updateNote(tripId, id, userId, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'deleteTripNote',
    summary: 'Delete a trip note',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Note ID' })
  @ApiNoContentResponse()
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Note not found' })
  deleteNote(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<void> {
    return this.tripNotesService.deleteNote(tripId, id, userId);
  }
}
