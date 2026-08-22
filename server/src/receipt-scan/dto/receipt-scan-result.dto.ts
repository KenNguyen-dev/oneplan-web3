import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class ReceiptItemDto {
  @ApiProperty({ description: 'Item name from the receipt' })
  name: string;

  @ApiProperty({ description: 'Quantity of the item', example: 1 })
  quantity: number;

  @ApiProperty({
    description: 'Price per unit in smallest currency unit',
    example: 25000,
  })
  unitPrice: number;

  @ApiProperty({
    description: 'Total price (quantity × unitPrice)',
    example: 50000,
  })
  totalPrice: number;
}

export class ReceiptScanResultDto {
  @ApiProperty({ type: [ReceiptItemDto], description: 'Parsed line items' })
  items: ReceiptItemDto[];

  @ApiPropertyOptional({ description: 'Subtotal before tax', example: 95000 })
  subtotal?: number;

  @ApiPropertyOptional({ description: 'Tax amount', example: 9500 })
  tax?: number;

  @ApiPropertyOptional({
    description: 'Total amount including tax',
    example: 104500,
  })
  total?: number;

  @ApiPropertyOptional({
    description: 'Currency code (e.g. VND, USD)',
    example: 'VND',
  })
  currency?: string;

  @ApiPropertyOptional({
    description: 'Restaurant or store name',
    example: 'Rituals Coffee House',
  })
  restaurantName?: string;
}
