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
  ApiBadRequestResponse,
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
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Public } from '../auth/decorators/public.decorator';
import { FriendsService } from './friends.service';
import { SendFriendRequestDto } from './dto/send-friend-request.dto';
import { RespondFriendRequestDto } from './dto/respond-friend-request.dto';
import { FriendPreviewDto } from './dto/friend-preview.dto';
import { FriendProfileDto } from './dto/friend-profile.dto';
import { FriendRequestDto } from './dto/friend-request.dto';
import { FriendDto } from './dto/friend.dto';
import { PublicFriendPreviewDto } from './dto/public-friend-preview.dto';

@ApiBearerAuth()
@ApiTags('Friends')
@Controller('friends')
export class FriendsController {
  constructor(private readonly friendsService: FriendsService) {}

  @Get('preview/:friendCode')
  @ApiOperation({
    operationId: 'previewFriend',
    summary: 'Preview a user profile by friend code',
  })
  @ApiParam({ name: 'friendCode', type: 'string' })
  @ApiOkResponse({ type: FriendPreviewDto })
  @ApiNotFoundResponse({ description: 'User not found' })
  previewFriend(
    @CurrentUser('sub') userId: number,
    @Param('friendCode') friendCode: string,
  ): Promise<FriendPreviewDto> {
    return this.friendsService.previewFriend(friendCode, userId);
  }

  @Public()
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  @Get('public-preview/:friendCode')
  @ApiOperation({
    operationId: 'getPublicFriendPreview',
    summary:
      'Public, no-auth preview by friend code for share-link landing pages',
  })
  @ApiParam({ name: 'friendCode', type: 'string' })
  @ApiOkResponse({ type: PublicFriendPreviewDto })
  @ApiNotFoundResponse({ description: 'User not found' })
  getPublicPreview(
    @Param('friendCode') friendCode: string,
  ): Promise<PublicFriendPreviewDto> {
    return this.friendsService.getPublicPreviewByCode(friendCode);
  }

  @Post('request')
  @ApiOperation({
    operationId: 'sendFriendRequest',
    summary: 'Send a friend request',
  })
  @ApiCreatedResponse({ description: 'Friend request sent' })
  @ApiBadRequestResponse({
    description: 'Cannot send request (self, duplicate, or already friends)',
  })
  @ApiNotFoundResponse({ description: 'User not found' })
  sendFriendRequest(
    @CurrentUser('sub') userId: number,
    @Body() dto: SendFriendRequestDto,
  ): Promise<void> {
    return this.friendsService.sendRequest(dto.friendCode, userId);
  }

  @Get('requests')
  @ApiOperation({
    operationId: 'listFriendRequests',
    summary: 'List pending incoming friend requests',
  })
  @ApiOkResponse({ type: [FriendRequestDto] })
  listFriendRequests(
    @CurrentUser('sub') userId: number,
  ): Promise<FriendRequestDto[]> {
    return this.friendsService.getPendingRequests(userId);
  }

  @Patch('request/:id/respond')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'respondToFriendRequest',
    summary: 'Accept or decline a friend request',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiNoContentResponse()
  @ApiNotFoundResponse({ description: 'Friend request not found' })
  @ApiForbiddenResponse({ description: 'Not your request' })
  respondToFriendRequest(
    @CurrentUser('sub') userId: number,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: RespondFriendRequestDto,
  ): Promise<void> {
    return this.friendsService.respondToRequest(id, userId, dto.accept);
  }

  @Delete('request/:friendCode')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'cancelSentFriendRequest',
    summary: 'Cancel a sent friend request',
  })
  @ApiParam({ name: 'friendCode', type: 'string' })
  @ApiNoContentResponse()
  @ApiNotFoundResponse({ description: 'Pending friend request not found' })
  @ApiForbiddenResponse({
    description: 'You can only cancel your own sent requests',
  })
  cancelSentFriendRequest(
    @CurrentUser('sub') userId: number,
    @Param('friendCode') friendCode: string,
  ): Promise<void> {
    return this.friendsService.cancelSentRequest(friendCode, userId);
  }

  @Get('profile/:userId')
  @ApiOperation({
    operationId: 'getUserFriendProfile',
    summary: 'Get a user profile with their friends list',
  })
  @ApiParam({ name: 'userId', type: 'integer' })
  @ApiOkResponse({ type: FriendProfileDto })
  @ApiNotFoundResponse({ description: 'User not found' })
  getUserFriendProfile(
    @CurrentUser('sub') currentUserId: number,
    @Param('userId', ParseIntPipe) userId: number,
  ): Promise<FriendProfileDto> {
    return this.friendsService.getUserProfile(userId, currentUserId);
  }

  @Get()
  @ApiOperation({
    operationId: 'listFriends',
    summary: 'List current user friends',
  })
  @ApiOkResponse({ type: [FriendDto] })
  listFriends(@CurrentUser('sub') userId: number): Promise<FriendDto[]> {
    return this.friendsService.getFriends(userId);
  }

  @Delete(':friendshipId')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ operationId: 'unfriend', summary: 'Remove a friend' })
  @ApiParam({ name: 'friendshipId', type: 'integer' })
  @ApiNoContentResponse()
  @ApiNotFoundResponse({ description: 'Friendship not found' })
  @ApiForbiddenResponse({ description: 'Not part of this friendship' })
  unfriend(
    @CurrentUser('sub') userId: number,
    @Param('friendshipId', ParseIntPipe) friendshipId: number,
  ): Promise<void> {
    return this.friendsService.unfriend(friendshipId, userId);
  }
}
