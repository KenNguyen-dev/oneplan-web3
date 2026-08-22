import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import {
  InviteStatus,
  TripEndRequestStatus,
  TripEndVoteDecision,
  TripStatus,
} from '@prisma/client';

import { TripEndConsensusService } from './trip-end-consensus.service';

describe('TripEndConsensusService', () => {
  const TRIP_ID = 10;
  const HOST = 1;
  const MEMBER = 2;

  function build(overrides: {
    existingRequest?: any;
    tripStatus?: TripStatus;
    createdById?: number;
    members?: { userId: number; displayName: string }[];
    votesAfterCreate?: { userId: number; decision: TripEndVoteDecision }[];
  }) {
    const members = overrides.members ?? [
      { userId: HOST, displayName: 'Host' },
      { userId: MEMBER, displayName: 'Member' },
    ];

    let requestRow = overrides.existingRequest ?? null;
    const votes: { userId: number; decision: TripEndVoteDecision }[] = [
      ...(requestRow?.votes ?? []),
    ];

    const prisma = {
      trip: {
        findUniqueOrThrow: jest.fn().mockResolvedValue({
          status: overrides.tripStatus ?? TripStatus.ONGOING,
          name: 'Da Lat',
        }),
        findUnique: jest.fn().mockResolvedValue({
          createdById: overrides.createdById ?? HOST,
        }),
        update: jest.fn().mockResolvedValue({}),
      },
      tripMember: {
        findUnique: jest.fn().mockImplementation(({ where }) => {
          const userId = where.tripId_userId.userId;
          const ok = members.some((m) => m.userId === userId);
          return Promise.resolve(
            ok
              ? { inviteStatus: InviteStatus.ACCEPTED, userId }
              : null,
          );
        }),
        findMany: jest.fn().mockResolvedValue(
          members.map((m) => ({
            userId: m.userId,
            user: { displayName: m.displayName, avatarUrl: null },
          })),
        ),
      },
      tripEndRequest: {
        findUnique: jest.fn().mockImplementation(() =>
          Promise.resolve(
            requestRow
              ? { ...requestRow, votes: [...votes] }
              : null,
          ),
        ),
        findUniqueOrThrow: jest.fn().mockImplementation(() =>
          Promise.resolve({ ...requestRow, votes: [...votes] }),
        ),
        create: jest.fn().mockImplementation(({ data }) => {
          requestRow = {
            id: 99,
            tripId: data.tripId,
            requestedBy: data.requestedBy,
            status: data.status,
            createdAt: new Date('2026-08-18T00:00:00.000Z'),
            resolvedAt: null,
            votes: [],
          };
          return Promise.resolve(requestRow);
        }),
        update: jest.fn().mockImplementation(({ data }) => {
          requestRow = { ...requestRow, ...data };
          return Promise.resolve(requestRow);
        }),
      },
      tripEndVote: {
        create: jest.fn().mockImplementation(({ data }) => {
          votes.push({
            userId: data.userId,
            decision: data.decision,
          });
          return Promise.resolve(data);
        }),
        deleteMany: jest.fn().mockImplementation(() => {
          votes.length = 0;
          return Promise.resolve({ count: 0 });
        }),
        findMany: jest.fn().mockImplementation(() => Promise.resolve([...votes])),
      },
      $transaction: jest.fn().mockImplementation(async (ops: unknown) => {
        if (Array.isArray(ops)) {
          return Promise.all(ops);
        }
        return ops;
      }),
    };

    const tripsHandler = {
      sendTripEndRequestUpdated: jest.fn(),
      sendTripEnded: jest.fn(),
    };
    const activityService = { log: jest.fn() };
    const vaultService = {
      requireVault: jest.fn().mockResolvedValue({ id: 1 }),
    };
    const vaultHistory = {
      getHistory: jest.fn().mockResolvedValue([]),
    };
    const vaultSettlement = {
      preview: jest.fn().mockResolvedValue({
        cashDebts: [],
        balanceMicro: '0',
      }),
      executeFromServer: jest.fn().mockResolvedValue({
        settled: true,
        signature: 'sig',
      }),
    };

    const service = new TripEndConsensusService(
      prisma as any,
      tripsHandler as any,
      activityService as any,
      vaultService as any,
      vaultHistory as any,
      vaultSettlement as any,
    );

    return {
      service,
      prisma,
      tripsHandler,
      vaultSettlement,
      setRequest(row: any) {
        requestRow = row;
        votes.length = 0;
        for (const vote of row.votes ?? []) {
          votes.push(vote);
        }
      },
    };
  }

  it('rejects non-creator starting end request', async () => {
    const { service } = build({});
    await expect(service.requestEnd(TRIP_ID, MEMBER)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('rejects double pending start', async () => {
    const { service, setRequest } = build({});
    setRequest({
      id: 1,
      tripId: TRIP_ID,
      requestedBy: HOST,
      status: TripEndRequestStatus.PENDING,
      createdAt: new Date(),
      resolvedAt: null,
      votes: [],
    });
    await expect(service.requestEnd(TRIP_ID, HOST)).rejects.toBeInstanceOf(
      ConflictException,
    );
  });

  it('deny marks request DENIED and does not settle', async () => {
    const { service, setRequest, vaultSettlement, tripsHandler } = build({});
    setRequest({
      id: 1,
      tripId: TRIP_ID,
      requestedBy: HOST,
      status: TripEndRequestStatus.PENDING,
      createdAt: new Date(),
      resolvedAt: null,
      votes: [],
    });

    const result = await service.castVote(
      TRIP_ID,
      MEMBER,
      TripEndVoteDecision.DENIED,
    );

    expect(result.status).toBe(TripEndRequestStatus.DENIED);
    expect(vaultSettlement.executeFromServer).not.toHaveBeenCalled();
    expect(tripsHandler.sendTripEnded).not.toHaveBeenCalled();
    expect(tripsHandler.sendTripEndRequestUpdated).toHaveBeenCalledWith(
      TRIP_ID,
      expect.objectContaining({
        status: TripEndRequestStatus.DENIED,
        deniedByUserId: MEMBER,
      }),
    );
  });

  it('unanimous approve ends trip and executes server settlement', async () => {
    const { service, setRequest, prisma, vaultSettlement, tripsHandler } =
      build({});
    setRequest({
      id: 1,
      tripId: TRIP_ID,
      requestedBy: HOST,
      status: TripEndRequestStatus.PENDING,
      createdAt: new Date(),
      resolvedAt: null,
      votes: [
        { userId: HOST, decision: TripEndVoteDecision.APPROVED },
      ],
    });

    const result = await service.castVote(
      TRIP_ID,
      MEMBER,
      TripEndVoteDecision.APPROVED,
    );

    expect(prisma.trip.update).toHaveBeenCalledWith({
      where: { id: TRIP_ID },
      data: { status: TripStatus.ENDED },
    });
    expect(vaultSettlement.executeFromServer).toHaveBeenCalledWith(TRIP_ID);
    expect(tripsHandler.sendTripEnded).toHaveBeenCalledWith(TRIP_ID);
    // Clients open TripEnd on tripEnded — settle must finish first or History
    // loads a pre-settlement balance / missing SETTLEMENT rows.
    const settleOrder =
      vaultSettlement.executeFromServer.mock.invocationCallOrder[0];
    const endedOrder = tripsHandler.sendTripEnded.mock.invocationCallOrder[0];
    expect(settleOrder).toBeLessThan(endedOrder);
    expect(result.status).toBe(TripEndRequestStatus.APPROVED);
  });

  it('rejects vote from non-member', async () => {
    const { service, setRequest } = build({});
    setRequest({
      id: 1,
      tripId: TRIP_ID,
      requestedBy: HOST,
      status: TripEndRequestStatus.PENDING,
      createdAt: new Date(),
      resolvedAt: null,
      votes: [],
    });
    await expect(
      service.castVote(TRIP_ID, 999, TripEndVoteDecision.APPROVED),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('rejects starting end when trip is not ongoing', async () => {
    const { service } = build({ tripStatus: TripStatus.ENDED });
    await expect(service.requestEnd(TRIP_ID, HOST)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('returns NotFound when no end request exists', async () => {
    const { service } = build({});
    await expect(service.getRequest(TRIP_ID, HOST)).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});
