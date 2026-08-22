import {
  Body,
  Controller,
  DefaultValuePipe,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Post,
  Query,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiCreatedResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiQuery,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { RecentLocationsService } from './recent-locations.service';
import { CreateRecentLocationDto } from './dto/create-recent-location.dto';
import { RecentLocationDto } from './dto/recent-location.dto';

@ApiBearerAuth()
@ApiTags('Recent Locations')
@Controller('auth/me/recent-locations')
export class RecentLocationsController {
  constructor(
    private readonly recentLocationsService: RecentLocationsService,
  ) {}

  @Get()
  @ApiOperation({
    operationId: 'listRecentLocations',
    summary: 'List recent locations',
  })
  @ApiQuery({
    name: 'limit',
    required: false,
    type: 'integer',
    description: 'Max results (default 10, max 50)',
  })
  @ApiOkResponse({ type: [RecentLocationDto] })
  listRecentLocations(
    @CurrentUser('sub') userId: number,
    @Query('limit', new DefaultValuePipe(10), ParseIntPipe) limit: number,
  ): Promise<RecentLocationDto[]> {
    return this.recentLocationsService.list(userId, Math.min(limit, 50));
  }

  @Post()
  @ApiOperation({
    operationId: 'saveRecentLocation',
    summary: 'Save a recent location',
  })
  @ApiCreatedResponse({ type: RecentLocationDto })
  saveRecentLocation(
    @CurrentUser('sub') userId: number,
    @Body() dto: CreateRecentLocationDto,
  ): Promise<RecentLocationDto> {
    return this.recentLocationsService.save(userId, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'deleteRecentLocation',
    summary: 'Delete a recent location',
  })
  @ApiParam({ name: 'id', type: 'integer', description: 'Recent location ID' })
  @ApiNoContentResponse()
  @ApiNotFoundResponse({ description: 'Recent location not found' })
  deleteRecentLocation(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<void> {
    return this.recentLocationsService.delete(userId, id);
  }
}
