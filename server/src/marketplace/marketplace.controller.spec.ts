import { MarketplaceController } from './marketplace.controller';
import { MarketplaceService } from './marketplace.service';

describe('MarketplaceController', () => {
  let controller: MarketplaceController;
  let marketplaceService: jest.Mocked<MarketplaceService>;

  beforeEach(() => {
    marketplaceService = {
      listMarketplaceFeed: jest.fn(),
      listPublicMarketplaceFeed: jest.fn(),
      createListing: jest.fn(),
      listMyListings: jest.fn(),
      getListing: jest.fn(),
      updateListing: jest.fn(),
      deleteListing: jest.fn(),
      createItem: jest.fn(),
      updateItem: jest.fn(),
      deleteItem: jest.fn(),
      applyForListing: jest.fn(),
      purchaseListing: jest.fn(),
      getAppliedStatus: jest.fn(),
      listMyAcquisitions: jest.fn(),
      getAcquisition: jest.fn(),
      createTripFromListing: jest.fn(),
    } as unknown as jest.Mocked<MarketplaceService>;

    controller = new MarketplaceController(marketplaceService);
  });

  it('delegates feed, listing, and item actions to MarketplaceService', async () => {
    const userId = 1;
    const listingId = 2;
    const itemId = 3;
    const take = 25;
    const listingDto = { name: 'Da Lat 3D2N' } as any;
    const itemDto = { title: 'Coffee stop' } as any;
    const listing = { id: listingId } as any;
    const item = { id: itemId } as any;
    const feed = {
      items: [{ id: listingId, name: 'Da Lat 3D2N' }],
      destinationNames: ['Da Lat'],
    } as any;

    marketplaceService.listMarketplaceFeed.mockResolvedValue(feed);
    marketplaceService.createListing.mockResolvedValue(listing);
    marketplaceService.listMyListings.mockResolvedValue([listing]);
    marketplaceService.getListing.mockResolvedValue(listing);
    marketplaceService.updateListing.mockResolvedValue(listing);
    marketplaceService.deleteListing.mockResolvedValue(undefined);
    marketplaceService.createItem.mockResolvedValue(item);
    marketplaceService.updateItem.mockResolvedValue(item);
    marketplaceService.deleteItem.mockResolvedValue(undefined);

    await controller.listMarketplaceFeed(userId, { take });
    await controller.createListing(userId, listingDto);
    await controller.listMyListings(userId);
    await controller.getListing(userId, String(listingId));
    await controller.updateListing(userId, listingId, listingDto);
    await controller.deleteListing(userId, listingId);
    await controller.createItem(userId, listingId, itemDto);
    await controller.updateItem(userId, listingId, itemId, itemDto);
    await controller.deleteItem(userId, listingId, itemId);

    expect(marketplaceService.listMarketplaceFeed).toHaveBeenCalledWith(
      { take },
      userId,
    );
    expect(marketplaceService.createListing).toHaveBeenCalledWith(
      userId,
      listingDto,
    );
    expect(marketplaceService.listMyListings).toHaveBeenCalledWith(userId);
    expect(marketplaceService.getListing).toHaveBeenCalledWith(
      String(listingId),
      userId,
      undefined,
    );
    expect(marketplaceService.updateListing).toHaveBeenCalledWith(
      listingId,
      userId,
      listingDto,
    );
    expect(marketplaceService.deleteListing).toHaveBeenCalledWith(
      listingId,
      userId,
    );
    expect(marketplaceService.createItem).toHaveBeenCalledWith(
      listingId,
      userId,
      itemDto,
    );
    expect(marketplaceService.updateItem).toHaveBeenCalledWith(
      listingId,
      itemId,
      userId,
      itemDto,
    );
    expect(marketplaceService.deleteItem).toHaveBeenCalledWith(
      listingId,
      itemId,
      userId,
    );
  });

  it('delegates the public feed to MarketplaceService and is marked @Public', async () => {
    const take = 10;
    const publicFeed = { items: [], featured: [], destinationNames: [] } as any;
    marketplaceService.listPublicMarketplaceFeed.mockResolvedValue(publicFeed);

    const result = await controller.listPublicMarketplaceFeed({ take });

    expect(marketplaceService.listPublicMarketplaceFeed).toHaveBeenCalledWith({
      take,
    });
    expect(result).toEqual(publicFeed);

    expect(
      Reflect.getMetadata('isPublic', controller.listPublicMarketplaceFeed),
    ).toBe(true);
  });

  it('delegates acquisition actions to MarketplaceService', async () => {
    const userId = 1;
    const listingId = 2;
    const purchaseDto = {
      packageName: 'com.oneplan.app',
      productId: 'marketplace.dalat.3d2n',
      purchaseToken: 'purchase-token',
    };
    const acquisition = {
      id: 10,
      userId,
      listingId,
      acquiredAt: '2026-03-28T00:00:00.000Z',
    } as any;
    const status = { applied: true, acquiredAt: '2026-03-28T00:00:00.000Z' };

    marketplaceService.applyForListing.mockResolvedValue(acquisition);
    marketplaceService.purchaseListing.mockResolvedValue(acquisition);
    marketplaceService.getAppliedStatus.mockResolvedValue(status);

    await controller.applyForListing(userId, listingId);
    await (controller as any).purchaseListing(userId, listingId, purchaseDto);
    await controller.getAppliedStatus(userId, listingId);

    expect(marketplaceService.applyForListing).toHaveBeenCalledWith(
      userId,
      listingId,
    );
    expect(marketplaceService.purchaseListing).toHaveBeenCalledWith(
      userId,
      listingId,
      purchaseDto,
    );
    expect(marketplaceService.getAppliedStatus).toHaveBeenCalledWith(
      userId,
      listingId,
    );
  });

  it('delegates createTripFromListing to MarketplaceService', async () => {
    const userId = 1;
    const listingId = 2;
    const trip = { id: 999, name: 'Da Lat Trip' } as any;

    marketplaceService.createTripFromListing.mockResolvedValue(trip);

    const result = await controller.createTripFromListing(userId, listingId);

    expect(marketplaceService.createTripFromListing).toHaveBeenCalledWith(
      userId,
      listingId,
    );
    expect(result).toEqual(trip);
  });
});
