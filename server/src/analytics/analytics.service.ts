import { Injectable, Logger } from '@nestjs/common';
import { ClsService } from 'nestjs-cls';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  type AnalyticsEventName,
  CLIENT_EMITTED_EVENTS,
} from './constants/events';
import { StartSessionDto } from './dto/start-session.dto';
import { TrackEventDto } from './dto/track-event.dto';

export interface TrackOptions {
  userId?: number | null;
  sessionId?: string | null;
  properties?: Record<string, unknown>;
  occurredAt?: Date;
}

@Injectable()
export class AnalyticsService {
  private readonly logger = new Logger(AnalyticsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly cls: ClsService,
  ) {}

  /**
   * Fire-and-forget event write. Never throws — analytics failures
   * must not break user flows.
   */
  async track(
    event: AnalyticsEventName,
    opts: TrackOptions = {},
  ): Promise<void> {
    try {
      const sessionId =
        opts.sessionId ?? this.cls.get<string>('sessionId') ?? null;
      const resolvedSessionId = await this.resolveSessionId(
        sessionId,
        opts.userId ?? null,
      );

      await this.prisma.analyticsEvent.create({
        data: {
          eventName: event,
          userId: opts.userId ?? null,
          sessionId: resolvedSessionId,
          properties:
            (opts.properties as Prisma.InputJsonValue) ?? Prisma.JsonNull,
          occurredAt: opts.occurredAt ?? new Date(),
        },
      });
    } catch (error) {
      this.logger.warn(`Failed to track analytics event ${event}: ${error}`);
    }
  }

  async startSession(
    input: StartSessionDto,
    userId: number | null,
  ): Promise<void> {
    // Idempotent: if the same session id arrives again (offline retry), attach
    // the userId now if it was previously anonymous. Also backfill the real
    // metadata — this call is authoritative and corrects a stub row that
    // resolveSessionId() may have lazily materialized from an earlier event that
    // raced ahead of this registration. Shared by the upsert `update` branch and
    // the P2002 retry below so the two can't drift.
    const update = {
      userId: userId ?? undefined,
      platform: input.platform,
      appVersion: input.appVersion ?? null,
      osVersion: input.osVersion ?? null,
      anonymousId: input.anonymousId ?? null,
      startedAt: new Date(input.startedAt),
    };
    try {
      await this.prisma.analyticsSession.upsert({
        where: { id: input.id },
        create: {
          id: input.id,
          userId,
          anonymousId: input.anonymousId ?? null,
          platform: input.platform,
          appVersion: input.appVersion ?? null,
          osVersion: input.osVersion ?? null,
          startedAt: new Date(input.startedAt),
        },
        update,
      });
    } catch (error) {
      // Same conditional-insert race as resolveSessionId(): a concurrent create
      // can win between this upsert's existence check and its insert, surfacing
      // as P2002. The row exists now, so apply our authoritative metadata via an
      // update. The retry stays inside this catch so it can't break the
      // fire-and-forget contract — if the row was deleted in between, the update
      // throws P2025 and is warned-and-swallowed like any other failure.
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        try {
          await this.prisma.analyticsSession.update({
            where: { id: input.id },
            data: update,
          });
          return;
        } catch (retryError) {
          this.logger.warn(
            `Failed to start analytics session ${input.id}: ${retryError}`,
          );
          return;
        }
      }
      this.logger.warn(
        `Failed to start analytics session ${input.id}: ${error}`,
      );
    }
  }

  async endSession(sessionId: string, endedAt: Date): Promise<void> {
    try {
      await this.prisma.analyticsSession.updateMany({
        where: { id: sessionId },
        data: { endedAt },
      });
    } catch (error) {
      this.logger.warn(
        `Failed to end analytics session ${sessionId}: ${error}`,
      );
    }
  }

  /**
   * Records a batch of client-emitted events. Rejects unknown event names
   * and events that are server-emitted only (those are written by domain
   * services directly, not via this endpoint).
   */
  async recordClientEvents(
    events: TrackEventDto[],
    ctx: { userId: number | null; sessionId: string | null },
  ): Promise<void> {
    const resolvedSessionId = await this.resolveSessionId(
      ctx.sessionId,
      ctx.userId,
    );
    const rows = events
      .filter((e) => CLIENT_EMITTED_EVENTS.has(e.eventName))
      .map((e) => ({
        eventName: e.eventName,
        userId: ctx.userId,
        sessionId: resolvedSessionId,
        properties: (e.properties as Prisma.InputJsonValue) ?? Prisma.JsonNull,
        occurredAt: new Date(e.occurredAt),
      }));

    if (rows.length === 0) return;

    try {
      await this.prisma.analyticsEvent.createMany({ data: rows });
    } catch (error) {
      this.logger.warn(
        `Failed to record ${rows.length} client analytics events: ${error}`,
      );
    }
  }

  /**
   * Resolves the session id for an event, lazily materializing the session
   * row when it doesn't exist yet.
   *
   * Events used to get `sessionId=null` whenever they raced ahead of
   * `POST /analytics/sessions` (or that registration was dropped, e.g. a
   * pre-auth 401 on the client). The fast path is unchanged (one indexed
   * `findUnique`); only when the session is genuinely missing do we upsert a
   * minimal stub so the event keeps its session reference. The authoritative
   * `startSession()` later backfills real platform/startedAt via its upsert
   * `update`. Never throws — analytics must not break user flows.
   */
  private async resolveSessionId(
    sessionId: string | null | undefined,
    userId: number | null,
  ): Promise<string | null> {
    if (!sessionId) return null;
    // `analytics_session.id` is VarChar(36). Reject anything that can't be a
    // session id rather than failing the event insert on a stub create.
    if (sessionId.length > 36) return null;
    try {
      const found = await this.prisma.analyticsSession.findUnique({
        where: { id: sessionId },
        select: { id: true },
      });
      if (found) return found.id;

      try {
        await this.prisma.analyticsSession.create({
          data: {
            id: sessionId,
            userId: userId ?? null,
            platform: 'unknown',
            startedAt: new Date(),
          },
        });
      } catch (error) {
        // findUnique→create is a TOCTOU race: when several events for the same
        // brand-new session arrive concurrently they all miss the read and then
        // collide on the insert. A P2002 here means a concurrent request already
        // created the row — exactly the state we wanted — so keep the event's
        // session reference instead of orphaning it. `id` is the only unique on
        // AnalyticsSession (the rest are plain @@index), so a P2002 can only be
        // the primary key; if a @@unique is ever added, narrow this on
        // `error.meta?.target`.
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === 'P2002'
        ) {
          return sessionId;
        }
        throw error;
      }
      return sessionId;
    } catch (error) {
      this.logger.warn(
        `Failed to materialize analytics session ${sessionId}: ${error}`,
      );
      return null;
    }
  }
}
