import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsUrl, MaxLength } from 'class-validator';

export class ExtractPinsRequestDto {
  @ApiProperty({
    description:
      'A public Instagram or TikTok video URL. Share URLs with tracking params can be long — the server canonicalizes the URL before storing it.',
    maxLength: 4000,
    example: 'https://www.instagram.com/reel/CxYzAbCdEfG/',
  })
  @IsString()
  @MaxLength(4000)
  @IsUrl({ require_protocol: true })
  sourceUrl: string;
}

export class StartPinExtractionResponseDto {
  @ApiProperty({ description: 'Session identifier; pass to the streaming GET' })
  sessionId: string;
}
