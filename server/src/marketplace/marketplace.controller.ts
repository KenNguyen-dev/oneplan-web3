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
  ApiQuery,
  ApiTags,
} from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Public } from '../auth/decorators/public.decorator';
import { MarketplaceService } from './marketplace.service';
import { CreateMarketplaceListingDto } from './dto/create-marketplace-listing.dto';
import { CreateDraftListingDto } from './dto/create-draft-listing.dto';
import { UpdateMarketplaceListingDto } from './dto/update-marketplace-listing.dto';
import { CreateMarketItemDto } from './dto/create-market-item.dto';
import { UpdateMarketItemDto } from './dto/update-market-item.dto';
import { MarketplaceListingDto } from './dto/marketplace-listing.dto';
import { MarketItemDto } from './dto/market-item.dto';
import { ListMarketplaceFeedQueryDto } from './dto/list-marketplace-feed-query.dto';
import { MarketplaceFeedDto } from './dto/marketplace-feed.dto';
import { PublicMarketplaceFeedDto } from './dto/public-marketplace-feed.dto';
import { CreatorProfileDto } from './dto/creator-profile.dto';
import { MarketplaceAcquisitionDto } from './dto/marketplace-acquisition.dto';
import { MarketplaceAppliedStatusDto } from './dto/marketplace-applied-status.dto';
import { CreateMarketplaceRatingDto } from './dto/create-marketplace-rating.dto';
import { MarketplaceRatingResponseDto } from './dto/marketplace-rating-response.dto';
import { MarketplaceAcquisitionSummaryDto } from './dto/marketplace-acquisition-summary.dto';
import { MarketplaceAcquisitionDetailDto } from './dto/marketplace-acquisition-detail.dto';
import { TripDto } from '../trips/dto/trip.dto';
import { PurchaseMarketplaceListingDto } from './dto/purchase-marketplace-listing.dto';

@ApiBearerAuth()
@ApiTags('Marketplace')
@Controller('marketplace')
export class MarketplaceController {
  constructor(private readonly marketplaceService: MarketplaceService) {}

  @Get('feed')
  @ApiOperation({
    operationId: 'listMarketplaceFeed',
    summary: 'List marketplace feed items',
  })
  @ApiOkResponse({ type: MarketplaceFeedDto })
  listMarketplaceFeed(
    @CurrentUser('sub') userId: number,
    @Query() query: ListMarketplaceFeedQueryDto,
  ): Promise<MarketplaceFeedDto> {
    return this.marketplaceService.listMarketplaceFeed(query, userId);
  }

  @Public()
  @Throttle({ default: { limit: 30, ttl: 60000 } })
  @Get('public/feed')
  @ApiOperation({
    operationId: 'listPublicMarketplaceFeed',
    summary:
      'Public marketplace feed (no auth) with the first 3 plan items per listing',
  })
  @ApiOkResponse({ type: PublicMarketplaceFeedDto })
  listPublicMarketplaceFeed(
    @Query() query: ListMarketplaceFeedQueryDto,
  ): Promise<PublicMarketplaceFeedDto> {
    return this.marketplaceService.listPublicMarketplaceFeed(query);
  }

  @Get('creators/:userId')
  @ApiOperation({
    operationId: 'getCreatorProfile',
    summary: 'Get a creator public profile with their listings',
  })
  @ApiParam({ name: 'userId', type: 'integer' })
  @ApiOkResponse({ type: CreatorProfileDto })
  @ApiNotFoundResponse({ description: 'Creator not found' })
  getCreatorProfile(
    @Param('userId', ParseIntPipe) userId: number,
  ): Promise<CreatorProfileDto> {
    return this.marketplaceService.getCreatorProfile(userId);
  }

  // ── Listing endpoints ──────────────────────────────────────────────

  @Post('listings')
  @ApiOperation({
    operationId: 'createListing',
    summary: 'Create a marketplace listing',
  })
  @ApiCreatedResponse({ type: MarketplaceListingDto })
  createListing(
    @CurrentUser('sub') userId: number,
    @Body() dto: CreateMarketplaceListingDto,
  ): Promise<MarketplaceListingDto> {
    return this.marketplaceService.createListing(userId, dto);
  }

  @Post('listings/draft')
  @ApiOperation({
    operationId: 'createDraftListing',
    summary: 'Create a draft marketplace listing (name + location only)',
  })
  @ApiCreatedResponse({ type: MarketplaceListingDto })
  createDraftListing(
    @CurrentUser('sub') userId: number,
    @Body() dto: CreateDraftListingDto,
  ): Promise<MarketplaceListingDto> {
    return this.marketplaceService.createDraftListing(userId, dto);
  }

  @Post('listings/:id/publish')
  @ApiOperation({
    operationId: 'publishListing',
    summary: 'Submit a draft listing for review (DRAFT → PENDING_REVIEW)',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: MarketplaceListingDto })
  @ApiForbiddenResponse({ description: 'Only the listing creator can publish' })
  @ApiNotFoundResponse({ description: 'Listing not found' })
  @ApiConflictResponse({ description: 'Only draft listings can be published' })
  publishListing(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<MarketplaceListingDto> {
    return this.marketplaceService.publishListing(id, userId);
  }

  @Get('listings')
  @ApiOperation({
    operationId: 'listMyListings',
    summary: 'List my marketplace listings',
  })
  @ApiOkResponse({ type: [MarketplaceListingDto] })
  listMyListings(
    @CurrentUser('sub') userId: number,
  ): Promise<MarketplaceListingDto[]> {
    return this.marketplaceService.listMyListings(userId);
  }

  @Get('listings/:id')
  @ApiOperation({
    operationId: 'getListing',
    summary: 'Get a marketplace listing by numeric ID or publicId',
  })
  @ApiParam({
    name: 'id',
    type: 'string',
    description:
      'Numeric listing ID or opaque publicId. Pass context=edit to require ownership.',
  })
  @ApiQuery({
    name: 'context',
    required: false,
    enum: ['edit'],
    description:
      'When set to "edit", the endpoint requires the current user to own the listing.',
  })
  @ApiOkResponse({ type: MarketplaceListingDto })
  @ApiNotFoundResponse({ description: 'Listing not found' })
  getListing(
    @CurrentUser('sub') userId: number,
    @Param('id') id: string,
    @Query('context') context?: string,
  ): Promise<MarketplaceListingDto> {
    return this.marketplaceService.getListing(id, userId, context);
  }

  @Patch('listings/:id')
  @ApiOperation({
    operationId: 'updateListing',
    summary: 'Update a marketplace listing',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: MarketplaceListingDto })
  @ApiForbiddenResponse({ description: 'Only the listing creator can update' })
  @ApiNotFoundResponse({ description: 'Listing not found' })
  updateListing(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateMarketplaceListingDto,
  ): Promise<MarketplaceListingDto> {
    return this.marketplaceService.updateListing(id, userId, dto);
  }

  @Delete('listings/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'deleteListing',
    summary: 'Delete a marketplace listing',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiNoContentResponse()
  @ApiForbiddenResponse({ description: 'Only the listing creator can delete' })
  @ApiNotFoundResponse({ description: 'Listing not found' })
  deleteListing(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<void> {
    return this.marketplaceService.deleteListing(id, userId);
  }

  // ── Acquisition endpoints ──────────────────────────────────────────

  @Post('listings/:id/apply')
  @ApiOperation({
    operationId: 'applyForListing',
    summary: 'Acquire a free marketplace listing',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiCreatedResponse({ type: MarketplaceAcquisitionDto })
  @ApiConflictResponse({ description: 'User already acquired this listing' })
  @ApiNotFoundResponse({ description: 'Listing not found' })
  applyForListing(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) listingId: number,
  ): Promise<MarketplaceAcquisitionDto> {
    return this.marketplaceService.applyForListing(userId, listingId);
  }

  @Post('listings/:id/purchase')
  @ApiOperation({
    operationId: 'purchaseListing',
    summary: 'Verify a paid marketplace purchase and acquire the listing',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiCreatedResponse({ type: MarketplaceAcquisitionDto })
  @ApiConflictResponse({ description: 'User already acquired this listing' })
  @ApiNotFoundResponse({ description: 'Listing not found' })
  purchaseListing(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) listingId: number,
    @Body() dto: PurchaseMarketplaceListingDto,
  ): Promise<MarketplaceAcquisitionDto> {
    return this.marketplaceService.purchaseListing(userId, listingId, dto);
  }

  @Get('listings/:id/applied')
  @ApiOperation({
    operationId: 'getAppliedStatus',
    summary: 'Check if the current user already applied for a listing',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: MarketplaceAppliedStatusDto })
  getAppliedStatus(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) listingId: number,
  ): Promise<MarketplaceAppliedStatusDto> {
    return this.marketplaceService.getAppliedStatus(userId, listingId);
  }

  @Get('acquisitions')
  @ApiOperation({
    operationId: 'listMyAcquisitions',
    summary: "List the current user's acquired plans (frozen snapshots)",
  })
  @ApiOkResponse({ type: [MarketplaceAcquisitionSummaryDto] })
  listMyAcquisitions(
    @CurrentUser('sub') userId: number,
  ): Promise<MarketplaceAcquisitionSummaryDto[]> {
    return this.marketplaceService.listMyAcquisitions(userId);
  }

  @Get('acquisitions/:id')
  @ApiOperation({
    operationId: 'getAcquisition',
    summary: 'Get an acquired plan with its snapshotted items',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: MarketplaceAcquisitionDetailDto })
  @ApiNotFoundResponse({ description: 'Acquisition not found' })
  getAcquisition(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<MarketplaceAcquisitionDetailDto> {
    return this.marketplaceService.getAcquisition(userId, id);
  }

  @Post('listings/:id/create-trip')
  @ApiOperation({
    operationId: 'createTripFromListing',
    summary: 'Create a new trip seeded from a marketplace listing',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiCreatedResponse({ type: TripDto })
  @ApiNotFoundResponse({ description: 'Listing not found' })
  createTripFromListing(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) listingId: number,
  ): Promise<TripDto> {
    return this.marketplaceService.createTripFromListing(userId, listingId);
  }

  // ── Rating endpoints ───────────────────────────────────────────────

  @Post('listings/:id/ratings')
  @ApiOperation({
    operationId: 'rateListing',
    summary: 'Rate a marketplace listing',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: MarketplaceRatingResponseDto })
  @ApiNotFoundResponse({ description: 'Listing not found' })
  @ApiForbiddenResponse({
    description: 'Must have acquired and applied to an ended trip',
  })
  rateListing(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: CreateMarketplaceRatingDto,
  ): Promise<MarketplaceRatingResponseDto> {
    return this.marketplaceService.rateListing(userId, id, dto);
  }

  // ── Item endpoints ─────────────────────────────────────────────────

  @Post('listings/:listingId/items')
  @ApiOperation({
    operationId: 'createMarketItem',
    summary: 'Add an item to a listing',
  })
  @ApiParam({ name: 'listingId', type: 'integer' })
  @ApiCreatedResponse({ type: MarketItemDto })
  @ApiForbiddenResponse({
    description: 'Only the listing creator can add items',
  })
  @ApiNotFoundResponse({ description: 'Listing not found' })
  createItem(
    @CurrentUser('sub') userId: number,
    @Param('listingId', ParseIntPipe) listingId: number,
    @Body() dto: CreateMarketItemDto,
  ): Promise<MarketItemDto> {
    return this.marketplaceService.createItem(listingId, userId, dto);
  }

  @Patch('listings/:listingId/items/:id')
  @ApiOperation({
    operationId: 'updateMarketItem',
    summary: 'Update an item in a listing',
  })
  @ApiParam({ name: 'listingId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Market item ID' })
  @ApiOkResponse({ type: MarketItemDto })
  @ApiForbiddenResponse({
    description: 'Only the listing creator can update items',
  })
  @ApiNotFoundResponse({ description: 'Market item not found' })
  updateItem(
    @CurrentUser('sub') userId: number,
    @Param('listingId', ParseIntPipe) listingId: number,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateMarketItemDto,
  ): Promise<MarketItemDto> {
    return this.marketplaceService.updateItem(listingId, id, userId, dto);
  }

  @Delete('listings/:listingId/items/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'deleteMarketItem',
    summary: 'Delete an item from a listing',
  })
  @ApiParam({ name: 'listingId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Market item ID' })
  @ApiNoContentResponse()
  @ApiForbiddenResponse({
    description: 'Only the listing creator can delete items',
  })
  @ApiNotFoundResponse({ description: 'Market item not found' })
  deleteItem(
    @CurrentUser('sub') userId: number,
    @Param('listingId', ParseIntPipe) listingId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<void> {
    return this.marketplaceService.deleteItem(listingId, id, userId);
  }
}
