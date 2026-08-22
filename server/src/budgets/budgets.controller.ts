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
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { BudgetsService } from './budgets.service';
import { BudgetDto } from './dto/budget.dto';
import { BudgetPaymentDto } from './dto/budget-payment.dto';
import { CreateBudgetDto } from './dto/create-budget.dto';
import { MarkPaymentDto } from './dto/mark-payment.dto';
import { UpdateBudgetDto } from './dto/update-budget.dto';

@ApiBearerAuth()
@ApiTags('Budgets')
@Controller('trips/:tripId/budgets')
export class BudgetsController {
  constructor(private readonly budgetsService: BudgetsService) {}

  @Post()
  @ApiOperation({ operationId: 'createBudget', summary: 'Create a new budget' })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiCreatedResponse({ type: BudgetDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  createBudget(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Body() dto: CreateBudgetDto,
  ): Promise<BudgetDto> {
    return this.budgetsService.createBudget(tripId, userId, dto);
  }

  @Get()
  @ApiOperation({
    operationId: 'listBudgets',
    summary: 'List all budgets for a trip',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiOkResponse({ type: [BudgetDto] })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  listBudgets(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
  ): Promise<BudgetDto[]> {
    return this.budgetsService.listBudgets(tripId, userId);
  }

  @Patch(':id')
  @ApiOperation({ operationId: 'updateBudget', summary: 'Update a budget' })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Budget ID' })
  @ApiOkResponse({ type: BudgetDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Budget not found' })
  updateBudget(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateBudgetDto,
  ): Promise<BudgetDto> {
    return this.budgetsService.updateBudget(tripId, id, userId, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ operationId: 'deleteBudget', summary: 'Delete a budget' })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Budget ID' })
  @ApiNoContentResponse()
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Budget not found' })
  deleteBudget(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<void> {
    return this.budgetsService.deleteBudget(tripId, id, userId);
  }

  @Patch(':id/payments/:paymentId')
  @ApiOperation({
    operationId: 'markBudgetPayment',
    summary: 'Mark a budget payment as paid or unpaid',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiParam({ name: 'id', type: 'integer', description: 'Budget ID' })
  @ApiParam({ name: 'paymentId', type: 'integer', description: 'Payment ID' })
  @ApiOkResponse({ type: BudgetPaymentDto })
  @ApiForbiddenResponse({
    description: 'Only the payment owner or trip creator can mark payments',
  })
  @ApiNotFoundResponse({ description: 'Payment not found' })
  markBudgetPayment(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Param('id', ParseIntPipe) id: number,
    @Param('paymentId', ParseIntPipe) paymentId: number,
    @Body() dto: MarkPaymentDto,
  ): Promise<BudgetPaymentDto> {
    return this.budgetsService.markBudgetPayment(
      tripId,
      id,
      paymentId,
      userId,
      dto,
    );
  }
}
