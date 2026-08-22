import {
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import {
  ActivityAction,
  Board,
  BoardPin,
  Currency,
  ExpenseCategory,
  InviteStatus,
} from '@prisma/client';
import { randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { GeminiService } from '../common/gemini/gemini.service';
import { StorageService } from '../storage/storage.service';
import { TripActivityService } from '../trip-activity/trip-activity.service';
import { TripsService } from '../trips/trips.service';
import { TripDto } from '../trips/dto/trip.dto';
import { BoardDto, BoardPinDto, BoardSummaryDto } from './dto/board.dto';
import { CreateBoardDto } from './dto/create-board.dto';
import { UpdateBoardDto } from './dto/update-board.dto';
import { AddPinsToBoardDto } from './dto/add-pins-to-board.dto';
import {
  BoardDescriptionDto,
  GenerateBoardDescriptionDto,
} from './dto/generate-board-description.dto';
import { GenerateTripFromBoardDto } from './dto/generate-trip-from-board.dto';

const DESCRIPTION_TIMEOUT_MS = 15_000;

// Gemini text arrange is a small payload, but gemini-2.5-flash adds a thinking
// phase by default and the first call also pays cold-start auth latency — 20s
// was too tight and aborted into the round-robin fallback. We disable thinking
// for this mechanical task (see arrangePins) and give the call generous head
// room; a genuinely stuck call still degrades to the even split.
const TRIP_GEN_TIMEOUT_MS = 45_000;

// Start times handed out per position within a day (morning → evening). Beyond
// the ladder we reuse the last slot rather than spilling past midnight.
const START_TIME_LADDER = ['09:00', '12:00', '15:00', '18:00', '20:00'];

// Board pins carry Gemini's free-form category vocabulary; map it onto the
// narrow ExpenseCategory enum. Anything unmapped/absent stays null.
const PIN_CATEGORY_MAP: Record<string, ExpenseCategory> = {
  restaurant: ExpenseCategory.FOOD,
  cafe: ExpenseCategory.FOOD,
  bar: ExpenseCategory.FOOD,
  hotel: ExpenseCategory.STAY,
  museum: ExpenseCategory.TICKET,
  landmark: ExpenseCategory.TICKET,
  viewpoint: ExpenseCategory.TICKET,
  park: ExpenseCategory.TICKET,
  beach: ExpenseCategory.TICKET,
  airport: ExpenseCategory.TRANSPORT,
  cinema: ExpenseCategory.TICKET,
  shop: ExpenseCategory.OTHER,
  grocery: ExpenseCategory.OTHER,
  gym: ExpenseCategory.OTHER,
  medical: ExpenseCategory.OTHER,
  spa: ExpenseCategory.OTHER,
  other: ExpenseCategory.OTHER,
};

// Gemini response schema (UPPERCASE types) for the arrange step. The model
// returns one assignment per input pin — id echoed verbatim, never invented.
// "suggestions" is only honoured when the caller opted into fillGaps.
const ARRANGE_RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    assignments: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        required: ['id', 'day', 'startTime'],
        properties: {
          id: { type: 'INTEGER' },
          day: { type: 'INTEGER' },
          startTime: { type: 'STRING' },
          mealSlot: { type: 'STRING' },
        },
      },
    },
    suggestions: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        required: [
          'name',
          'day',
          'startTime',
          'latitude',
          'longitude',
          'address',
        ],
        properties: {
          name: { type: 'STRING' },
          day: { type: 'INTEGER' },
          startTime: { type: 'STRING' },
          latitude: { type: 'NUMBER' },
          longitude: { type: 'NUMBER' },
          address: { type: 'STRING' },
          category: { type: 'STRING' },
        },
      },
    },
  },
};

interface RawSuggestion {
  name: string;
  day: number;
  startTime: string;
  latitude: number;
  longitude: number;
  address?: string;
  category?: string;
}

interface ArrangeResult {
  assignments: {
    id: number;
    day: number;
    startTime: string;
    mealSlot?: string;
  }[];
  suggestions?: RawSuggestion[];
}

// One resolved plan-item placement after reconciling Gemini's output (or the
// fallback) against the authoritative pin list.
interface PinPlacement {
  pin: BoardPin;
  dayNumber: number;
  startTime: string;
  sortOrder: number;
}

const SUGGESTED_DESCRIPTION = '✨ Suggested by AI';
const MAX_SUGGESTIONS_PER_DAY = 3;

// A validated AI-suggested venue placed on a day (only when fillGaps=true).
interface SuggestionPlacement {
  name: string;
  dayNumber: number;
  startTime: string;
  latitude: number;
  longitude: number;
  address: string | null;
  category: ExpenseCategory | null;
  sortOrder: number;
}

// Two pins are considered the same place if they fall within this distance
// AND have matching names (see isDuplicatePin).
const PIN_DEDUPE_RADIUS_M = 50;

interface PinMatchInput {
  name: string;
  latitude?: number | null;
  longitude?: number | null;
}

const DESCRIPTION_SYSTEM_PROMPT = `You write short, friendly travel-board descriptions.

Rules:
- Output ONLY the description text. No JSON, no preamble, no quotes.
- 2–3 sentences, max 80 words.
- Be specific to the place: mention a known vibe, neighborhood, food, or scene.
- Avoid clichés like "vibrant city of contrasts" or "something for everyone".
- Write in friendly second person where natural.`;

type BoardWithLocation = Board & {
  city?: { name: string } | null;
  state?: { name: string } | null;
  country?: { name: string } | null;
};

@Injectable()
export class BoardService {
  private readonly logger = new Logger(BoardService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly storageService: StorageService,
    private readonly gemini: GeminiService,
    private readonly tripsService: TripsService,
    private readonly activityService: TripActivityService,
  ) {}

  private async resolveCoverImageUrl(
    objectKey: string | null | undefined,
  ): Promise<string | undefined> {
    if (!objectKey) return undefined;
    try {
      const { url } = await this.storageService.getSignedThumbUrl(objectKey);
      return url;
    } catch (error) {
      this.logger.warn(
        `Failed to sign board cover URL for ${objectKey}: ${(error as Error).message}`,
      );
      return undefined;
    }
  }

  async listMyBoards(userId: number): Promise<BoardSummaryDto[]> {
    const rows = await this.prisma.board.findMany({
      where: { userId },
      orderBy: { updatedAt: 'desc' },
      include: {
        _count: { select: { pins: true } },
        city: { select: { name: true } },
        state: { select: { name: true } },
        country: { select: { name: true } },
      },
    });
    return Promise.all(
      rows.map(async (row) => ({
        ...this.toSummary(row, row._count.pins),
        coverImageUrl: await this.resolveCoverImageUrl(row.coverImageUrl),
      })),
    );
  }

  async createBoard(
    userId: number,
    dto: CreateBoardDto,
  ): Promise<BoardSummaryDto> {
    const board = await this.prisma.board.create({
      data: {
        userId,
        title: dto.title,
        description: dto.description,
        coverImageUrl: dto.coverImageUrl,
        cityId: dto.cityId,
        stateId: dto.stateId,
        countryId: dto.countryId,
      },
      include: {
        city: { select: { name: true } },
        state: { select: { name: true } },
        country: { select: { name: true } },
      },
    });
    return {
      ...this.toSummary(board, 0),
      coverImageUrl: await this.resolveCoverImageUrl(board.coverImageUrl),
    };
  }

  async updateBoard(
    userId: number,
    boardId: number,
    dto: UpdateBoardDto,
  ): Promise<BoardSummaryDto> {
    const existing = await this.prisma.board.findUnique({
      where: { id: boardId },
      select: { id: true, userId: true },
    });
    if (!existing) throw new NotFoundException('Board not found');
    if (existing.userId !== userId) {
      throw new ForbiddenException('You do not own this board');
    }

    // Prisma skips `undefined` fields, so an omitted location/title is left
    // untouched — the iOS client sends `nil` for anything the user didn't edit.
    const board = await this.prisma.board.update({
      where: { id: boardId },
      data: {
        title: dto.title,
        description: dto.description,
        cityId: dto.cityId,
        stateId: dto.stateId,
        countryId: dto.countryId,
      },
      include: {
        _count: { select: { pins: true } },
        city: { select: { name: true } },
        state: { select: { name: true } },
        country: { select: { name: true } },
      },
    });

    return {
      ...this.toSummary(board, board._count.pins),
      coverImageUrl: await this.resolveCoverImageUrl(board.coverImageUrl),
    };
  }

  async getBoard(userId: number, boardId: number): Promise<BoardDto> {
    const board = await this.prisma.board.findUnique({
      where: { id: boardId },
      include: {
        pins: { orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }] },
        city: { select: { name: true } },
        state: { select: { name: true } },
        country: { select: { name: true } },
      },
    });
    if (!board) throw new NotFoundException('Board not found');
    if (board.userId !== userId) {
      throw new ForbiddenException('You do not own this board');
    }
    return {
      id: board.id,
      title: board.title,
      description: board.description ?? undefined,
      coverImageUrl: await this.resolveCoverImageUrl(board.coverImageUrl),
      cityId: board.cityId ?? undefined,
      stateId: board.stateId ?? undefined,
      countryId: board.countryId ?? undefined,
      locationLabel: this.formatLocationLabel(board),
      pins: board.pins.map((p) => this.toPinDto(p)),
      createdAt: board.createdAt.toISOString(),
      updatedAt: board.updatedAt.toISOString(),
    };
  }

  async addPinsToBoard(
    userId: number,
    boardId: number,
    dto: AddPinsToBoardDto,
  ): Promise<BoardDto> {
    const board = await this.prisma.board.findUnique({
      where: { id: boardId },
      select: { id: true, userId: true },
    });
    if (!board) throw new NotFoundException('Board not found');
    if (board.userId !== userId) {
      throw new ForbiddenException('You do not own this board');
    }

    const existing = await this.prisma.boardPin.findMany({
      where: { boardId },
      select: { name: true, latitude: true, longitude: true },
    });

    // Silently drop pins that already exist on the board. Seed the "seen" set
    // with what's already there, then grow it with each accepted pin so
    // duplicates *within this payload* are also collapsed. The skip is
    // intentionally invisible to the client — it just gets the updated board.
    const seen: PinMatchInput[] = [...existing];
    const accepted: AddPinsToBoardDto['pins'] = [];

    for (const pin of dto.pins) {
      const isDup = seen.some((s) => this.isDuplicatePin(pin, s));
      if (isDup) continue;
      seen.push(pin);
      accepted.push(pin);
    }

    if (accepted.length > 0) {
      const currentMaxOrder = await this.prisma.boardPin.aggregate({
        where: { boardId },
        _max: { sortOrder: true },
      });
      const startOrder = (currentMaxOrder._max.sortOrder ?? -1) + 1;

      await this.prisma.boardPin.createMany({
        data: accepted.map((pin, idx) => ({
          boardId,
          name: pin.name,
          address: pin.address,
          latitude: pin.latitude,
          longitude: pin.longitude,
          notes: pin.notes,
          sourceUrl: pin.sourceUrl,
          sourceTimestampSec: pin.sourceTimestampSec,
          category: pin.category,
          dayNumber: pin.dayNumber,
          timeOfDayText: pin.timeOfDayText,
          sortOrder: startOrder + idx,
        })),
      });

      await this.prisma.board.update({
        where: { id: boardId },
        data: { updatedAt: new Date() },
      });
    }

    return this.getBoard(userId, boardId);
  }

  async deleteBoard(userId: number, boardId: number): Promise<void> {
    const board = await this.prisma.board.findUnique({
      where: { id: boardId },
      select: { id: true, userId: true, coverImageUrl: true },
    });
    if (!board) throw new NotFoundException('Board not found');
    if (board.userId !== userId) {
      throw new ForbiddenException('You do not own this board');
    }
    await this.prisma.board.delete({ where: { id: boardId } });
    if (board.coverImageUrl) {
      try {
        await this.storageService.deleteObject(board.coverImageUrl);
      } catch (error) {
        this.logger.warn(
          `Failed to delete board cover ${board.coverImageUrl}: ${(error as Error).message}`,
        );
      }
    }
  }

  async deleteBoardPin(
    userId: number,
    boardId: number,
    pinId: number,
  ): Promise<void> {
    const board = await this.prisma.board.findUnique({
      where: { id: boardId },
      select: { id: true, userId: true },
    });
    if (!board) throw new NotFoundException('Board not found');
    if (board.userId !== userId) {
      throw new ForbiddenException('You do not own this board');
    }

    const pin = await this.prisma.boardPin.findUnique({
      where: { id: pinId },
      select: { id: true, boardId: true },
    });
    if (!pin || pin.boardId !== boardId) {
      throw new NotFoundException('Pin not found on this board');
    }

    await this.prisma.boardPin.delete({ where: { id: pinId } });
    await this.prisma.board.update({
      where: { id: boardId },
      data: { updatedAt: new Date() },
    });
  }

  async generateDescription(
    dto: GenerateBoardDescriptionDto,
  ): Promise<BoardDescriptionDto> {
    const locationLabel = [dto.cityName, dto.stateName, dto.countryName]
      .filter((part): part is string => Boolean(part && part.trim()))
      .join(', ');
    const fallback = this.buildFallbackDescription(dto.title, locationLabel);

    // System rules + the per-board ask, combined into one Gemini prompt.
    const prompt = `${DESCRIPTION_SYSTEM_PROMPT}

Write a description for a travel board titled "${dto.title}" focused on ${locationLabel || dto.title}.`;

    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      DESCRIPTION_TIMEOUT_MS,
    );

    try {
      const text = await this.gemini.generateText({
        prompt,
        signal: controller.signal,
      });
      const content = text.trim();
      if (!content) return { description: fallback };

      const trimmed = content.length > 500 ? content.slice(0, 500) : content;
      return { description: trimmed };
    } catch (error) {
      // Vertex not configured / API error / timeout — degrade to the
      // templated description (same resilience as the old OpenAI path).
      this.logger.warn(
        `Gemini description generation failed: ${(error as Error).message}`,
      );
      return { description: fallback };
    } finally {
      clearTimeout(timeout);
    }
  }

  // Arrange the selected board pins into a multi-day trip. Gemini groups the
  // pins by geography and assigns each a day + start time; we create the trip,
  // its creator-member, and one plan item per pin in a single transaction, then
  // return the fully-mapped TripDto. The AI is "arrange-only" — it never invents
  // places, and any unusable output degrades to an even round-robin split.
  async generateTrip(
    userId: number,
    boardId: number,
    dto: GenerateTripFromBoardDto,
  ): Promise<TripDto> {
    const board = await this.prisma.board.findUnique({
      where: { id: boardId },
      select: {
        id: true,
        userId: true,
        cityId: true,
        stateId: true,
        countryId: true,
      },
    });
    if (!board) throw new NotFoundException('Board not found');
    if (board.userId !== userId) {
      throw new ForbiddenException('You do not own this board');
    }

    const pins = await this.prisma.boardPin.findMany({
      where: { boardId, id: { in: dto.pinIds } },
    });
    if (pins.length !== dto.pinIds.length) {
      throw new NotFoundException('One or more pins are not on this board');
    }

    // Never spread fewer pins across more days than we have pins.
    const dayCount = Math.min(dto.dayCount, pins.length);

    const { placements, suggestions } = await this.arrangePins(
      pins,
      dayCount,
      dto.fillGaps ?? false,
    );

    // Default the trip currency to the user's preference (mirrors createTrip;
    // do NOT rely on the schema default, which is VND).
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { preferredCurrency: true },
    });
    const currency = user?.preferredCurrency ?? Currency.USD;
    const inviteCode = randomBytes(32).toString('hex');

    const trip = await this.prisma.$transaction(async (tx) => {
      const created = await tx.trip.create({
        data: {
          name: dto.tripName,
          currency,
          createdById: userId,
          inviteCode,
          // The generated trip's destination is the board's location.
          cityId: board.cityId,
          stateId: board.stateId,
          countryId: board.countryId,
        },
      });

      await tx.tripMember.create({
        data: {
          tripId: created.id,
          userId,
          inviteStatus: InviteStatus.ACCEPTED,
          joinedAt: new Date(),
        },
      });

      for (const placement of placements) {
        const item = await tx.tripPlanItem.create({
          data: {
            tripId: created.id,
            title: placement.pin.name,
            description: placement.pin.notes,
            location: placement.pin.address,
            latitude: placement.pin.latitude,
            longitude: placement.pin.longitude,
            address: placement.pin.address,
            startTime: placement.startTime,
            category: this.mapPinCategory(placement.pin.category),
            sortOrder: placement.sortOrder,
            dayNumber: placement.dayNumber,
            planDate: null,
          },
        });
        await tx.tripPlanItemMember.create({
          data: { tripPlanItemId: item.id, userId },
        });
      }

      for (const suggestion of suggestions) {
        const item = await tx.tripPlanItem.create({
          data: {
            tripId: created.id,
            title: suggestion.name,
            description: SUGGESTED_DESCRIPTION,
            location: suggestion.address,
            latitude: suggestion.latitude,
            longitude: suggestion.longitude,
            address: suggestion.address,
            startTime: suggestion.startTime,
            category: suggestion.category,
            sortOrder: suggestion.sortOrder,
            dayNumber: suggestion.dayNumber,
            planDate: null,
          },
        });
        await tx.tripPlanItemMember.create({
          data: { tripPlanItemId: item.id, userId },
        });
      }

      return created;
    });

    void this.activityService.log(
      trip.id,
      userId,
      ActivityAction.TRIP_CREATED,
      undefined,
      { name: dto.tripName },
    );

    return this.tripsService.getTrip(trip.id, userId);
  }

  // Ask Gemini to assign each pin a day + start time, then reconcile the result
  // against the authoritative pin set. The schema can't guarantee set-equality,
  // so we drop invented ids, fill missing pins round-robin, dedupe, and clamp
  // the day range. Any error/abort/empty result falls back to a full even split.
  private async arrangePins(
    pins: BoardPin[],
    dayCount: number,
    fillGaps: boolean,
  ): Promise<{
    placements: PinPlacement[];
    suggestions: SuggestionPlacement[];
  }> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), TRIP_GEN_TIMEOUT_MS);

    try {
      const prompt = this.buildArrangePrompt(pins, dayCount, fillGaps);
      const result = await this.gemini.generateJsonFromText<ArrangeResult>({
        prompt,
        responseSchema: ARRANGE_RESPONSE_SCHEMA,
        signal: controller.signal,
        temperature: 0,
        // Arranging a fixed list by geography needs no chain-of-thought;
        // disabling it cuts latency (the abort cause) and adds determinism.
        thinkingBudget: 0,
      });
      const placements = this.reconcileAssignments(
        pins,
        dayCount,
        result?.assignments,
      );
      const suggestions = fillGaps
        ? this.reconcileSuggestions(
            pins,
            dayCount,
            result?.suggestions,
            placements,
          )
        : [];
      return { placements, suggestions };
    } catch (error) {
      this.logger.warn(
        `Gemini trip arrange failed, using round-robin: ${(error as Error).message}`,
      );
      return {
        placements: this.roundRobinPlacements(pins, dayCount),
        suggestions: [],
      };
    } finally {
      clearTimeout(timeout);
    }
  }

  private buildArrangePrompt(
    pins: BoardPin[],
    dayCount: number,
    fillGaps: boolean,
  ): string {
    const places = pins.map((p) => ({
      id: p.id,
      name: p.name,
      latitude: p.latitude,
      longitude: p.longitude,
      category: p.category,
      // Schedule narrated in the source video, when known — strong hints.
      knownDay: p.dayNumber ?? undefined,
      knownTime: p.timeOfDayText ?? undefined,
    }));
    // "MUST" is deliberate: at temperature 0 with thinking disabled, a
    // permissive "MAY add" makes the model return an empty suggestions array
    // every time (verified against real board pins). The user explicitly
    // opted in, so empty meal slots must actually get filled.
    const suggestionRules = fillGaps
      ? `
- After assigning, check every day for missing meals: each day MUST have a breakfast (~08:00), a lunch (~12:00), and a dinner (~18:30). For EVERY meal slot that has no assigned place, you MUST add exactly one entry to "suggestions": a real, well-known venue near that day's cluster (its real name, its real street "address" as found on a map, its real latitude/longitude — the venue's actual coordinates, never a city-centre placeholder and never the same point for two venues — a category from [restaurant, cafe, bar], the day, and a startTime for that slot). Max 3 suggestions per day. Never suggest a place already in the list, and never put suggestions in "assignments".`
      : '';
    const returnShape = fillGaps
      ? `Return JSON: { "assignments": [ { "id", "day", "startTime", "mealSlot" } ], "suggestions": [ { "name", "day", "startTime", "latitude", "longitude", "address", "category" } ] } with one assignment per place.`
      : `Return JSON: { "assignments": [ { "id", "day", "startTime", "mealSlot" } ] } with one entry per place.`;
    return `You are planning a ${dayCount}-day trip itinerary.

Rules:
- Use ONLY the places listed below in "assignments". Copy each "id" verbatim — never invent, drop, merge, or rename a place.
- Assign every place to exactly one day, numbered 1 to ${dayCount}.
- Home base: if exactly one place has an accommodation category (hotel), it is the trip's fixed home base. Assign it to day 1 with an afternoon check-in startTime (around 14:00), and cluster every day's places around it. Do not schedule it again on later days.
- Daily rhythm: breakfast around 08:00, morning sightseeing, lunch around 12:00, afternoon sightseeing or a café stop around 15:00, dinner around 18:30, then optionally one evening spot around 20:00.
- Place food places (restaurant, cafe, bar) into meal slots — set "mealSlot" to one of "breakfast", "lunch", "dinner", or "snack" for them, choosing by proximity to that day's cluster. Leave "mealSlot" out for non-food places.
- Spread sightseeing places evenly across the days — at most 4 per day.
- If a place has "knownDay" or "knownTime" (its schedule from the original travel video), prefer that day and a startTime consistent with that time mention. Cluster the remaining places around them.
- Group places that are geographically close on the same day to minimise travel.
- If the places span multiple distant regions or countries, keep each region on its own contiguous block of days — never mix far-apart regions on the same day.
- Within each day, order places sensibly and give each a 24-hour "startTime" as "HH:MM" running from morning to evening.${suggestionRules}

${returnShape}

Places:
${JSON.stringify(places)}`;
  }

  // Build final placements from the model's assignments, trusting only ids that
  // exist in the input. Missing pins are appended round-robin. sortOrder is
  // re-derived per day by startTime so the plan reads top-to-bottom.
  private reconcileAssignments(
    pins: BoardPin[],
    dayCount: number,
    assignments: ArrangeResult['assignments'] | undefined,
  ): PinPlacement[] {
    const pinById = new Map(pins.map((p) => [p.id, p]));
    const dayByPinId = new Map<number, number>();

    // Pins with a day narrated in the source video (BoardPin.dayNumber — not
    // the AI-arranged PinPlacement day) keep it, clamped to the trip length.
    for (const pin of pins) {
      if (pin.dayNumber != null) {
        dayByPinId.set(pin.id, Math.min(Math.max(pin.dayNumber, 1), dayCount));
      }
    }

    for (const a of assignments ?? []) {
      if (!pinById.has(a.id) || dayByPinId.has(a.id)) continue; // unknown/dup
      const day = Math.min(Math.max(Math.round(a.day), 1), dayCount);
      dayByPinId.set(a.id, day);
    }

    // Any pin the model skipped gets spread across the remaining days.
    let fillCursor = 0;
    for (const pin of pins) {
      if (!dayByPinId.has(pin.id)) {
        dayByPinId.set(pin.id, (fillCursor % dayCount) + 1);
        fillCursor++;
      }
    }

    const startTimeByPinId = new Map<number, string>();
    for (const a of assignments ?? []) {
      if (pinById.has(a.id) && this.isValidTime(a.startTime)) {
        startTimeByPinId.set(a.id, a.startTime);
      }
    }

    return this.buildPlacements(pins, dayByPinId, startTimeByPinId);
  }

  // Defensively validate the model's suggested venues (only requested when
  // fillGaps=true): sane coords, in-range day, valid time, non-empty unique
  // name, ≤3/day. Bad suggestions are dropped silently — they are additive
  // extras and must never fail the request. sortOrder interleaves them with
  // that day's pins by startTime, renumbering the pins' sortOrder to match.
  private reconcileSuggestions(
    pins: BoardPin[],
    dayCount: number,
    raw: RawSuggestion[] | undefined,
    placements: PinPlacement[],
  ): SuggestionPlacement[] {
    const pinNames = new Set(pins.map((p) => p.name.trim().toLowerCase()));
    const countByDay = new Map<number, number>();
    const accepted: SuggestionPlacement[] = [];

    for (const s of raw ?? []) {
      const name = typeof s.name === 'string' ? s.name.trim() : '';
      const day = Math.round(Number(s.day));
      if (
        !name ||
        name.length > 255 ||
        pinNames.has(name.toLowerCase()) ||
        !Number.isFinite(s.latitude) ||
        s.latitude < -90 ||
        s.latitude > 90 ||
        !Number.isFinite(s.longitude) ||
        s.longitude < -180 ||
        s.longitude > 180 ||
        !Number.isInteger(day) ||
        day < 1 ||
        day > dayCount ||
        !this.isValidTime(s.startTime)
      ) {
        continue;
      }
      const used = countByDay.get(day) ?? 0;
      if (used >= MAX_SUGGESTIONS_PER_DAY) continue;
      countByDay.set(day, used + 1);
      pinNames.add(name.toLowerCase()); // no duplicate suggestions either
      // Address is display-only — a missing/empty one never rejects an
      // otherwise-valid suggestion.
      const address =
        typeof s.address === 'string' && s.address.trim()
          ? s.address.trim().slice(0, 500)
          : null;
      accepted.push({
        name,
        dayNumber: day,
        startTime: s.startTime,
        latitude: s.latitude,
        longitude: s.longitude,
        address,
        category: this.mapPinCategory(s.category),
        sortOrder: 0, // assigned below
      });
    }

    // Renumber sortOrder per day across pins + suggestions, ordered by time.
    const days = new Set<number>([
      ...placements.map((p) => p.dayNumber),
      ...accepted.map((s) => s.dayNumber),
    ]);
    for (const day of days) {
      const combined: { startTime: string; setOrder: (n: number) => void }[] = [
        ...placements
          .filter((p) => p.dayNumber === day)
          .map((p) => ({
            startTime: p.startTime,
            setOrder: (n: number) => (p.sortOrder = n),
          })),
        ...accepted
          .filter((s) => s.dayNumber === day)
          .map((s) => ({
            startTime: s.startTime,
            setOrder: (n: number) => (s.sortOrder = n),
          })),
      ];
      combined
        .sort((a, b) => a.startTime.localeCompare(b.startTime))
        .forEach((entry, i) => entry.setOrder(i));
    }
    return accepted;
  }

  private roundRobinPlacements(
    pins: BoardPin[],
    dayCount: number,
  ): PinPlacement[] {
    const dayByPinId = new Map<number, number>();
    pins.forEach((pin, i) => dayByPinId.set(pin.id, (i % dayCount) + 1));
    return this.buildPlacements(pins, dayByPinId, new Map());
  }

  // Group pins by their assigned day, keep any model-provided start time (else
  // hand out the ladder by position), and number sortOrder within each day.
  private buildPlacements(
    pins: BoardPin[],
    dayByPinId: Map<number, number>,
    startTimeByPinId: Map<number, string>,
  ): PinPlacement[] {
    const byDay = new Map<number, BoardPin[]>();
    for (const pin of pins) {
      const day = dayByPinId.get(pin.id) ?? 1;
      const list = byDay.get(day) ?? [];
      list.push(pin);
      byDay.set(day, list);
    }

    const placements: PinPlacement[] = [];
    for (const day of [...byDay.keys()].sort((a, b) => a - b)) {
      const dayPins = byDay.get(day)!;
      // Order by any provided start time so the ladder fallback fills the gaps
      // in a stable, readable sequence.
      dayPins.sort((a, b) => {
        const ta = startTimeByPinId.get(a.id) ?? '';
        const tb = startTimeByPinId.get(b.id) ?? '';
        return ta.localeCompare(tb);
      });
      dayPins.forEach((pin, i) => {
        placements.push({
          pin,
          dayNumber: day,
          startTime:
            startTimeByPinId.get(pin.id) ??
            START_TIME_LADDER[Math.min(i, START_TIME_LADDER.length - 1)],
          sortOrder: i,
        });
      });
    }
    return placements;
  }

  private isValidTime(value: unknown): value is string {
    return typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
  }

  private mapPinCategory(
    category: string | null | undefined,
  ): ExpenseCategory | null {
    if (!category) return null;
    return PIN_CATEGORY_MAP[category.toLowerCase()] ?? null;
  }

  async setCoverImageUrl(boardId: number, url: string): Promise<void> {
    await this.prisma.board.update({
      where: { id: boardId },
      data: { coverImageUrl: url },
    });
  }

  private buildFallbackDescription(title: string, locationLabel: string) {
    const place = locationLabel || title;
    return `A collection of pins from ${place}. Save the spots you love and plan your next trip in one place.`;
  }

  private toSummary(
    board: BoardWithLocation,
    pinCount: number,
  ): BoardSummaryDto {
    return {
      id: board.id,
      title: board.title,
      description: board.description ?? undefined,
      coverImageUrl: board.coverImageUrl ?? undefined,
      cityId: board.cityId ?? undefined,
      stateId: board.stateId ?? undefined,
      countryId: board.countryId ?? undefined,
      locationLabel: this.formatLocationLabel(board),
      pinCount,
      createdAt: board.createdAt.toISOString(),
      updatedAt: board.updatedAt.toISOString(),
    };
  }

  private formatLocationLabel(board: BoardWithLocation): string | undefined {
    const parts = [
      board.city?.name,
      board.state?.name,
      board.country?.name,
    ].filter((p): p is string => Boolean(p));
    return parts.length ? parts.join(', ') : undefined;
  }

  // "Café Apartment 42" -> "cafe apartment 42". Lowercase, strip accents,
  // collapse anything non-alphanumeric to single spaces.
  private normalizePinName(name: string): string {
    return name
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/gu, '')
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  }

  private haversineMeters(
    aLat: number,
    aLng: number,
    bLat: number,
    bLng: number,
  ): number {
    const R = 6_371_000;
    const toRad = (d: number) => (d * Math.PI) / 180;
    const dLat = toRad(bLat - aLat);
    const dLng = toRad(bLng - aLng);
    const lat1 = toRad(aLat);
    const lat2 = toRad(bLat);
    const h =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(h));
  }

  // True when `candidate` is the same place as `existing`.
  //  - Empty normalized name on either side -> never a match (name is the only
  //    disambiguator; if it's gone, don't suppress).
  //  - Both have coords within PIN_DEDUPE_RADIUS_M: match on exact normalized
  //    name, OR (both names have >=2 tokens AND the smaller token-set is a
  //    subset of the larger). Single-token names ("starbucks") need an exact
  //    match so distinct nearby venues aren't collapsed.
  //  - Otherwise (coords missing): exact normalized-name equality only.
  private isDuplicatePin(
    candidate: PinMatchInput,
    existing: PinMatchInput,
  ): boolean {
    const a = this.normalizePinName(candidate.name);
    const b = this.normalizePinName(existing.name);
    if (!a || !b) return false;

    const hasGeo =
      candidate.latitude != null &&
      candidate.longitude != null &&
      existing.latitude != null &&
      existing.longitude != null;

    // Both sides geocoded: same place only if physically close AND the names
    // corroborate it. Far-apart pins are never dupes even with identical names
    // (e.g. two different "Starbucks").
    if (hasGeo) {
      const meters = this.haversineMeters(
        candidate.latitude!,
        candidate.longitude!,
        existing.latitude!,
        existing.longitude!,
      );
      if (meters > PIN_DEDUPE_RADIUS_M) return false;
      if (a === b) return true;
      const at = a.split(' ');
      const bt = b.split(' ');
      if (at.length >= 2 && bt.length >= 2) {
        const [small, large] = at.length <= bt.length ? [at, bt] : [bt, at];
        const largeSet = new Set(large);
        return small.every((t) => largeSet.has(t));
      }
      return false;
    }

    // Coords missing on at least one side: fall back to exact normalized name.
    return a === b;
  }

  private toPinDto(pin: BoardPin): BoardPinDto {
    return {
      id: pin.id,
      boardId: pin.boardId,
      name: pin.name,
      address: pin.address ?? undefined,
      latitude: pin.latitude ?? undefined,
      longitude: pin.longitude ?? undefined,
      notes: pin.notes ?? undefined,
      sourceUrl: pin.sourceUrl ?? undefined,
      sourceTimestampSec: pin.sourceTimestampSec ?? undefined,
      category: pin.category ?? undefined,
      dayNumber: pin.dayNumber ?? undefined,
      timeOfDayText: pin.timeOfDayText ?? undefined,
      sortOrder: pin.sortOrder,
      createdAt: pin.createdAt.toISOString(),
    };
  }

  // Exposed for tests that need direct access without going through findMany.
  toBoardSummary(board: Board, pinCount: number): BoardSummaryDto {
    return {
      id: board.id,
      title: board.title,
      description: board.description ?? undefined,
      coverImageUrl: board.coverImageUrl ?? undefined,
      cityId: board.cityId ?? undefined,
      stateId: board.stateId ?? undefined,
      countryId: board.countryId ?? undefined,
      pinCount,
      createdAt: board.createdAt.toISOString(),
      updatedAt: board.updatedAt.toISOString(),
    };
  }
}
