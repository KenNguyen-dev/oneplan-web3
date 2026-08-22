import { Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { FriendsService } from '../friends/friends.service';
import { MarketplaceService } from '../marketplace/marketplace.service';
import { TripsService } from '../trips/trips.service';
import { DeeplinksController } from './deeplinks.controller';

function makeConfig(values: Record<string, string | undefined>): ConfigService {
  return {
    getOrThrow: jest.fn((key: string) => {
      if (key === 'GCS_PUBLIC_BUCKET') return 'oneplan-public';
      throw new Error(`unexpected key: ${key}`);
    }),
    get: jest.fn((key: string) => values[key]),
  } as unknown as ConfigService;
}

describe('DeeplinksController', () => {
  let controller: DeeplinksController;
  let tripsService: Pick<TripsService, 'getInvitePreview'>;
  let friendsService: Pick<FriendsService, 'getPublicPreviewByCode'>;
  let marketplaceService: Pick<MarketplaceService, 'getPublicListingPreview'>;

  function makeController(
    values: Record<string, string | undefined>,
  ): DeeplinksController {
    return new DeeplinksController(
      tripsService as unknown as TripsService,
      friendsService as unknown as FriendsService,
      marketplaceService as unknown as MarketplaceService,
      makeConfig(values),
    );
  }

  beforeEach(() => {
    tripsService = { getInvitePreview: jest.fn() };
    friendsService = { getPublicPreviewByCode: jest.fn() };
    marketplaceService = { getPublicListingPreview: jest.fn() };

    controller = makeController({
      ANDROID_APP_PACKAGE_NAME: 'com.oneplan.android',
      ANDROID_APP_SHA256_CERT_FINGERPRINTS: 'AA:BB:CC, DD:EE:FF',
    });
  });

  describe('getAppleAppSiteAssociation', () => {
    it('returns the AASA payload with the bundle appID and friend/join components', () => {
      const aasa = controller.getAppleAppSiteAssociation();

      expect(aasa).toEqual({
        applinks: {
          details: [
            {
              appIDs: ['GS4TMK323X.lumilabs.oneplan'],
              components: [
                { '/': '/friend/*', comment: 'Friend invites' },
                { '/': '/join/*', comment: 'Trip invites' },
                { '/': '/listing/*', comment: 'Marketplace listings' },
              ],
            },
          ],
        },
      });
    });

    it('uses IOS_APP_IDS so dev can serve the dev bundle instead of prod', () => {
      const devController = makeController({
        IOS_APP_IDS: ' GS4TMK323X.dev.lumilabs.oneplan , ',
        ANDROID_APP_PACKAGE_NAME: 'com.oneplan.android',
        ANDROID_APP_SHA256_CERT_FINGERPRINTS: 'AA:BB:CC',
      });

      expect(
        devController.getAppleAppSiteAssociation().applinks.details[0].appIDs,
      ).toEqual(['GS4TMK323X.dev.lumilabs.oneplan']);
    });
  });

  describe('getAndroidAssetLinks', () => {
    it('returns a Digital Asset Links statement with the package and fingerprints (legacy env vars)', () => {
      const links = controller.getAndroidAssetLinks();

      expect(links).toEqual([
        {
          relation: ['delegate_permission/common.handle_all_urls'],
          target: {
            namespace: 'android_app',
            package_name: 'com.oneplan.android',
            sha256_cert_fingerprints: ['AA:BB:CC', 'DD:EE:FF'],
          },
        },
      ]);
    });

    it('fails closed with an empty array and logs a warning when no fingerprints are configured', () => {
      const warnSpy = jest
        .spyOn(Logger.prototype, 'warn')
        .mockImplementation(() => undefined);

      const c = makeController({
        ANDROID_APP_PACKAGE_NAME: 'com.oneplan.android',
        ANDROID_APP_SHA256_CERT_FINGERPRINTS: '',
      });

      expect(c.getAndroidAssetLinks()).toEqual([]);
      expect(warnSpy).toHaveBeenCalledWith(
        expect.stringContaining('will NOT verify'),
      );

      warnSpy.mockRestore();
    });

    it('does not warn once at least one package has fingerprints configured', () => {
      const warnSpy = jest
        .spyOn(Logger.prototype, 'warn')
        .mockImplementation(() => undefined);

      makeController({
        ANDROID_APP_PACKAGE_NAME: 'com.oneplan.android',
        ANDROID_APP_SHA256_CERT_FINGERPRINTS: 'AA:BB:CC',
      });

      expect(warnSpy).not.toHaveBeenCalled();
      warnSpy.mockRestore();
    });

    it('serves one statement per package when ANDROID_APP_LINK_TARGETS declares multiple apps', () => {
      const c = makeController({
        ANDROID_APP_LINK_TARGETS:
          'com.oneplan.android:AA:BB:CC,DD:EE:FF;com.oneplan.android.dev:11:22:33',
      });

      expect(c.getAndroidAssetLinks()).toEqual([
        {
          relation: ['delegate_permission/common.handle_all_urls'],
          target: {
            namespace: 'android_app',
            package_name: 'com.oneplan.android',
            sha256_cert_fingerprints: ['AA:BB:CC', 'DD:EE:FF'],
          },
        },
        {
          relation: ['delegate_permission/common.handle_all_urls'],
          target: {
            namespace: 'android_app',
            package_name: 'com.oneplan.android.dev',
            sha256_cert_fingerprints: ['11:22:33'],
          },
        },
      ]);
    });

    it('normalizes fingerprints to uppercase and trims surrounding whitespace', () => {
      const c = makeController({
        ANDROID_APP_LINK_TARGETS: 'com.oneplan.android: aa:bb:cc , dd:ee:ff ',
      });

      expect(c.getAndroidAssetLinks()).toEqual([
        {
          relation: ['delegate_permission/common.handle_all_urls'],
          target: {
            namespace: 'android_app',
            package_name: 'com.oneplan.android',
            sha256_cert_fingerprints: ['AA:BB:CC', 'DD:EE:FF'],
          },
        },
      ]);
    });

    it('skips a package declared with no fingerprints while still serving configured ones', () => {
      const warnSpy = jest
        .spyOn(Logger.prototype, 'warn')
        .mockImplementation(() => undefined);

      const c = makeController({
        ANDROID_APP_LINK_TARGETS:
          'com.oneplan.android:AA:BB:CC;com.oneplan.android.dev:',
      });

      expect(c.getAndroidAssetLinks()).toEqual([
        {
          relation: ['delegate_permission/common.handle_all_urls'],
          target: {
            namespace: 'android_app',
            package_name: 'com.oneplan.android',
            sha256_cert_fingerprints: ['AA:BB:CC'],
          },
        },
      ]);
      expect(warnSpy).not.toHaveBeenCalled();
      warnSpy.mockRestore();
    });
  });

  describe('friendLanding', () => {
    it('uses per-user copy when the friend code resolves', async () => {
      (friendsService.getPublicPreviewByCode as jest.Mock).mockResolvedValue({
        displayName: 'Carol',
        tripCount: 4,
      });

      const html = await controller.friendLanding('CAROL-CODE');

      expect(html).toContain('Add Carol on OnePlan');
      expect(html).toContain('Carol has sent you a friend request.');
      expect(html).toContain(
        'https://storage.googleapis.com/oneplan-public/og/og-friend.png',
      );
      expect(html).toContain('oneplan://friend/CAROL-CODE');
    });

    it('falls back to generic copy + og-friend.png when friend code is invalid', async () => {
      (friendsService.getPublicPreviewByCode as jest.Mock).mockRejectedValue(
        new NotFoundException('User not found'),
      );

      const html = await controller.friendLanding('BAD-CODE');

      expect(html).toContain('Join me on OnePlan');
      expect(html).toContain(
        'Someone invited you to connect on OnePlan. Install the app to accept.',
      );
      expect(html).toContain(
        'https://storage.googleapis.com/oneplan-public/og/og-friend.png',
      );
      expect(html).toContain('oneplan://friend/BAD-CODE');
    });
  });

  describe('joinLanding', () => {
    it('always uses og-trip.png even when the trip has a cover image', async () => {
      (tripsService.getInvitePreview as jest.Mock).mockResolvedValue({
        name: 'Da Lat 2026',
        coverImageUrl: 'https://signed.example/cover.jpg',
        memberCount: 3,
      });

      const html = await controller.joinLanding('TRIP-CODE');

      // Quotes get HTML-escaped in the rendered output.
      expect(html).toContain('Join &quot;Da Lat 2026&quot; on OnePlan');
      expect(html).toContain('3 travelers on this trip. Tap to join.');
      expect(html).toContain(
        'https://storage.googleapis.com/oneplan-public/og/og-trip.png',
      );
      // Per design decision: do NOT inject the trip cover into og:image.
      expect(html).not.toContain('https://signed.example/cover.jpg');
    });

    it('falls back to generic copy when invite code is invalid', async () => {
      (tripsService.getInvitePreview as jest.Mock).mockRejectedValue(
        new NotFoundException('Invalid invite code'),
      );

      const html = await controller.joinLanding('NOPE');

      expect(html).toContain('Join this trip on OnePlan');
      // Apostrophe is HTML-escaped to &#39; in the rendered output.
      expect(html).toContain(
        'You&#39;ve been invited to plan a trip together.',
      );
    });
  });

  describe('listingLanding', () => {
    it('uses per-listing copy + og-listing.png when the listing resolves', async () => {
      (
        marketplaceService.getPublicListingPreview as jest.Mock
      ).mockResolvedValue({
        name: 'Da Lat 3D2N',
        creatorName: 'Vivian',
        durationDays: 3,
      });

      const html = await controller.listingLanding('123');

      expect(html).toContain('Da Lat 3D2N on OnePlan');
      // Apostrophe is HTML-escaped to &#39; in the rendered output.
      expect(html).toContain(
        'Vivian&#39;s 3-day plan. Tap to view on OnePlan.',
      );
      expect(html).toContain(
        'https://storage.googleapis.com/oneplan-public/og/og-listing.png',
      );
      expect(html).toContain('oneplan://listing/123');
    });

    it('falls back to generic copy when the listing is missing/non-approved', async () => {
      (
        marketplaceService.getPublicListingPreview as jest.Mock
      ).mockRejectedValue(new NotFoundException('Listing not found'));

      const html = await controller.listingLanding('999');

      expect(html).toContain('Check out this trip plan on OnePlan');
      expect(html).toContain(
        'A curated trip plan on OnePlan. Install the app to view and use it.',
      );
      expect(html).toContain(
        'https://storage.googleapis.com/oneplan-public/og/og-listing.png',
      );
      expect(html).toContain('oneplan://listing/999');
    });
  });
});
