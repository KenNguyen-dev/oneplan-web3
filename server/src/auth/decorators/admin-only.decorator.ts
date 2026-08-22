import { applyDecorators, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiForbiddenResponse } from '@nestjs/swagger';
import { AdminGuard } from '../guards/admin.guard';

export function AdminOnly() {
  return applyDecorators(
    UseGuards(AdminGuard),
    ApiBearerAuth(),
    ApiForbiddenResponse({ description: 'Admin access required' }),
  );
}
