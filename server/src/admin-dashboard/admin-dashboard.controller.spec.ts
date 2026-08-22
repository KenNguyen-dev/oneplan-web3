import { AdminDashboardController } from './admin-dashboard.controller';
import { AdminDashboardService } from './admin-dashboard.service';

describe('AdminDashboardController', () => {
  let controller: AdminDashboardController;
  let service: jest.Mocked<AdminDashboardService>;

  beforeEach(() => {
    service = {
      listUsers: jest.fn(),
      listAnalyticsEvents: jest.fn(),
      getAnalyticsSummary: jest.fn(),
      getUsersAggregates: jest.fn(),
      getUserDetail: jest.fn(),
      getTripsAggregates: jest.fn(),
      listTrips: jest.fn(),
    } as unknown as jest.Mocked<AdminDashboardService>;

    controller = new AdminDashboardController(service);
  });

  it('delegates listUsers to the service with the query DTO', async () => {
    const result = { items: [], total: 0, page: 1, limit: 25 } as any;
    service.listUsers.mockResolvedValue(result);

    await expect(
      controller.listUsers({ page: 2, limit: 10, search: 'alice' }),
    ).resolves.toBe(result);

    expect(service.listUsers).toHaveBeenCalledWith({
      page: 2,
      limit: 10,
      search: 'alice',
    });
  });

  it('delegates listAnalyticsEvents to the service', async () => {
    const result = { items: [], total: 0, page: 1, limit: 50 } as any;
    service.listAnalyticsEvents.mockResolvedValue(result);

    await expect(
      controller.listAnalyticsEvents({ page: 1, limit: 50 }),
    ).resolves.toBe(result);

    expect(service.listAnalyticsEvents).toHaveBeenCalledWith({
      page: 1,
      limit: 50,
    });
  });

  it('delegates listAnalyticsEvents with platform filter to the service', async () => {
    const result = { items: [], total: 0, page: 1, limit: 50 } as any;
    service.listAnalyticsEvents.mockResolvedValue(result);

    await expect(
      controller.listAnalyticsEvents({
        page: 1,
        limit: 50,
        platform: 'android',
      }),
    ).resolves.toBe(result);

    expect(service.listAnalyticsEvents).toHaveBeenCalledWith({
      page: 1,
      limit: 50,
      platform: 'android',
    });
  });

  it('delegates getUsersAggregates to the service', async () => {
    const result = {
      totalUsers: 100,
      signupsByDay: [],
      byAuthProvider: [],
      bySubscriptionStatus: [],
      bySubscriptionProduct: [],
      activeSubscriptions: 12,
      activePayOnce: 3,
      newSubsByDay: [],
      churnByDay: [],
      topActiveUsers: [],
    } as any;
    service.getUsersAggregates.mockResolvedValue(result);

    await expect(
      controller.getUsersAggregates({ from: '2026-01-01' }),
    ).resolves.toBe(result);

    expect(service.getUsersAggregates).toHaveBeenCalledWith({
      from: '2026-01-01',
    });
  });

  it('delegates getUserDetail to the service with the parsed id', async () => {
    const result = { user: { id: 42 } } as any;
    service.getUserDetail.mockResolvedValue(result);

    await expect(controller.getUserDetail(42)).resolves.toBe(result);
    expect(service.getUserDetail).toHaveBeenCalledWith(42);
  });

  it('delegates getAnalyticsSummary to the service', async () => {
    const result = {
      range: { from: new Date(), to: new Date() },
      totalEvents: 0,
      totalUsers: 0,
      byEventName: [],
      byDay: [],
      byPlatform: [],
    } as any;
    service.getAnalyticsSummary.mockResolvedValue(result);

    await expect(controller.getAnalyticsSummary({})).resolves.toBe(result);

    expect(service.getAnalyticsSummary).toHaveBeenCalledWith({});
  });

  it('delegates getTripsAggregates to the service', async () => {
    const result = { totalTrips: 5 } as any;
    service.getTripsAggregates.mockResolvedValue(result);

    await expect(
      controller.getTripsAggregates({ from: '2026-01-01' }),
    ).resolves.toBe(result);

    expect(service.getTripsAggregates).toHaveBeenCalledWith({
      from: '2026-01-01',
    });
  });

  it('delegates listTrips to the service with the query DTO', async () => {
    const result = { items: [], total: 0, page: 1, limit: 25 } as any;
    service.listTrips.mockResolvedValue(result);

    await expect(
      controller.listTrips({ page: 1, limit: 25, search: 'dalat' }),
    ).resolves.toBe(result);

    expect(service.listTrips).toHaveBeenCalledWith({
      page: 1,
      limit: 25,
      search: 'dalat',
    });
  });
});
