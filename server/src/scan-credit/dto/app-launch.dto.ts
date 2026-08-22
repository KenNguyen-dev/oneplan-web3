import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

// Posted by the iOS client on launch so the server can grant the per-version
// app-update reward. `appVersion` is CFBundleShortVersionString (e.g. "1.2.5").
export class AppLaunchDto {
  @ApiProperty({
    description: 'The running app version (CFBundleShortVersionString).',
    example: '1.2.5',
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(32)
  appVersion: string;
}
