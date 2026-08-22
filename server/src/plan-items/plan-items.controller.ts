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
  Query,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiConflictResponse,
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
import { PlanItemsService } from './plan-items.service';
import { AddMembersDto } from './dto/add-members.dto';
import { CreatePlanItemDto } from './dto/create-plan-item.dto';
import { ListPlanItemsQueryDto } from './dto/list-plan-items-query.dto';
import { PlanItemDto } from './dto/plan-item.dto';
import { PlanItemMemberDto } from './dto/plan-item-member.dto';
import { UpdatePlanItemDto } from './dto/update-plan-item.dto';

@ApiBearerAuth()
@ApiTags('Plan Items')
@Controller('trips/:tripId/plan-items')
export class PlanItemsController {
  constructor(private readonly planItemsService: PlanItemsService) {}

  @Post()
  @ApiOperation({
    operationId: 'createPlanItem',
    summary: 'Create a new plan item',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiCreatedResponse({ type: PlanItemDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  createPlanItem(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Body() dto: CreatePlanItemDto,
  ): Promise<PlanItemDto> {
    return this.planItemsService.createPlanItem(tripId, userId, dto);
  }

  @Get()
  @ApiOperation({
    operationId: 'listPlanItems',
    summary: 'List plan items for a specific date',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiOkResponse({ type: [PlanItemDto] })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  listPlanItems(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Query() query: ListPlanItemsQueryDto,
  ): Promise<PlanItemDto[]> {
    return this.planItemsService.listPlanItems(
      tripId,
      userId,
      query.planDate,
      query.dayNumber,
    );
  }

  @Get(':id')
  @ApiOperation({
    operationId: 'getPlanItem',
    summary: 'Get a plan item by ID',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Plan item ID' })
  @ApiOkResponse({ type: PlanItemDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Plan item not found' })
  getPlanItem(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<PlanItemDto> {
    return this.planItemsService.getPlanItem(tripId, id, userId);
  }

  @Patch(':id')
  @ApiOperation({
    operationId: 'updatePlanItem',
    summary: 'Update a plan item',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Plan item ID' })
  @ApiOkResponse({ type: PlanItemDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Plan item not found' })
  updatePlanItem(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdatePlanItemDto,
  ): Promise<PlanItemDto> {
    return this.planItemsService.updatePlanItem(tripId, id, userId, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'deletePlanItem',
    summary: 'Delete a plan item',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Plan item ID' })
  @ApiNoContentResponse()
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Plan item not found' })
  deletePlanItem(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<void> {
    return this.planItemsService.deletePlanItem(tripId, id, userId);
  }

  @Post(':id/members')
  @ApiOperation({
    operationId: 'addPlanItemMembers',
    summary: 'Add members to a plan item',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Plan item ID' })
  @ApiCreatedResponse({ type: [PlanItemMemberDto] })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Plan item not found' })
  addPlanItemMembers(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: AddMembersDto,
  ): Promise<PlanItemMemberDto[]> {
    return this.planItemsService.addPlanItemMembers(tripId, id, userId, dto);
  }

  @Delete(':id/members/:userId')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'removePlanItemMember',
    summary: 'Remove a member from a plan item',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Plan item ID' })
  @ApiParam({
    name: 'userId',
    type: 'integer',
    description: 'User ID to remove',
  })
  @ApiNoContentResponse()
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Member not found on this plan item' })
  removePlanItemMember(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
    @Param('userId', ParseIntPipe) targetUserId: number,
  ): Promise<void> {
    return this.planItemsService.removePlanItemMember(
      tripId,
      id,
      targetUserId,
      userId,
    );
  }

  @Post('apply-acquisition/:acquisitionId')
  @ApiOperation({
    operationId: 'applyAcquisitionToTrip',
    summary: 'Apply an acquired marketplace plan (snapshot) to this trip',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({
    name: 'acquisitionId',
    type: 'integer',
    description: 'Marketplace acquisition ID owned by the current user',
  })
  @ApiCreatedResponse({ type: [PlanItemDto] })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({
    description: 'Acquisition not found or has no items',
  })
  @ApiConflictResponse({ description: 'Plan already applied to this trip' })
  applyAcquisitionToTrip(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('acquisitionId', ParseIntPipe) acquisitionId: number,
  ): Promise<PlanItemDto[]> {
    return this.planItemsService.applyAcquisitionToTrip(
      tripId,
      acquisitionId,
      userId,
    );
  }
}
