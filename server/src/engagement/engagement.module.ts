import { Module } from '@nestjs/common';
import { GeminiModule } from '../common/gemini/gemini.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { WeatherModule } from '../weather/weather.module';
import { EngagementCopyService } from './engagement-copy.service';
import { EngagementCronService } from './engagement.cron';
import { EngagementFrequencyService } from './engagement-frequency.service';
import { EngagementTargetingService } from './engagement-targeting.service';
import { ENGAGEMENT_EVALUATORS, TriggerEvaluator } from './engagement.types';
import { DormantEvaluator } from './triggers/dormant.evaluator';
import { NewPlanEvaluator } from './triggers/new-plan.evaluator';
import { UnfinishedPlanEvaluator } from './triggers/unfinished-plan.evaluator';
import { WeatherEvaluator } from './triggers/weather.evaluator';

// AnalyticsModule and PrismaModule are @Global. Gemini/Notifications/Weather
// are explicit imports.
@Module({
  imports: [GeminiModule, NotificationsModule, WeatherModule],
  providers: [
    EngagementCronService,
    EngagementTargetingService,
    EngagementCopyService,
    EngagementFrequencyService,
    DormantEvaluator,
    UnfinishedPlanEvaluator,
    WeatherEvaluator,
    NewPlanEvaluator,
    {
      provide: ENGAGEMENT_EVALUATORS,
      useFactory: (
        dormant: DormantEvaluator,
        unfinished: UnfinishedPlanEvaluator,
        weather: WeatherEvaluator,
        newPlan: NewPlanEvaluator,
      ): TriggerEvaluator[] => [dormant, unfinished, weather, newPlan],
      inject: [
        DormantEvaluator,
        UnfinishedPlanEvaluator,
        WeatherEvaluator,
        NewPlanEvaluator,
      ],
    },
  ],
})
export class EngagementModule {}
