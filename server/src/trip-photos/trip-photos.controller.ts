import {
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Query,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiForbiddenResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { TripPhotosService } from './trip-photos.service';
import { ListTripPhotosQueryDto } from './dto/list-trip-photos-query.dto';
import { TripPhotoDto } from './dto/trip-photo.dto';
import { TripPhotoListDto } from './dto/trip-photo-list.dto';

@ApiBearerAuth()
@ApiTags('Trip Photos')
@Controller('trips/:tripId/photos')
export class TripPhotosController {
  constructor(private readonly tripPhotosService: TripPhotosService) {}

  @Get()
  @ApiOperation({
    operationId: 'listTripPhotos',
    summary: 'List photos for a trip',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiOkResponse({ type: TripPhotoListDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  listPhotos(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Query() query: ListTripPhotosQueryDto,
  ): Promise<TripPhotoListDto> {
    return this.tripPhotosService.listPhotos(
      tripId,
      userId,
      query.cursor,
      query.take,
    );
  }

  @Get(':id')
  @ApiOperation({ operationId: 'getTripPhoto', summary: 'Get a trip photo' })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Photo ID' })
  @ApiOkResponse({ type: TripPhotoDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Photo not found' })
  getPhoto(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<TripPhotoDto> {
    return this.tripPhotosService.getPhoto(tripId, id, userId);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'deleteTripPhoto',
    summary: 'Delete a trip photo',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Photo ID' })
  @ApiNoContentResponse()
  @ApiForbiddenResponse({
    description: 'Not a member of this trip or not authorized to delete',
  })
  @ApiNotFoundResponse({ description: 'Photo not found' })
  deletePhoto(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<void> {
    return this.tripPhotosService.deletePhoto(tripId, id, userId);
  }
}
