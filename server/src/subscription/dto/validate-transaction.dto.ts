import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsNotEmpty } from 'class-validator';

export class ValidateTransactionDto {
  @ApiProperty({
    description: 'JWS-encoded transaction from StoreKit 2',
    example: 'eyJhbGciOiJFUzI1NiIs...',
  })
  @IsString()
  @IsNotEmpty()
  jws: string;
}
