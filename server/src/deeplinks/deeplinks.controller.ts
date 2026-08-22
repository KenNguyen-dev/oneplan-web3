import { Controller, Get, Header, Logger, Param } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SkipThrottle } from '@nestjs/throttler';
import { ApiExcludeController } from '@nestjs/swagger';
import { Public } from '../auth/decorators/public.decorator';
import { FriendsService } from '../friends/friends.service';
import { MarketplaceService } from '../marketplace/marketplace.service';
import { TripsService } from '../trips/trips.service';

// Default (prod) iOS app ID. Dev overrides via IOS_APP_IDS so that
// dev-op.oneplan.space associates with the dev bundle (dev.lumilabs.oneplan)
// instead of the App Store build — otherwise iOS hands dev links to prod.
const DEFAULT_IOS_APP_IDS = ['GS4TMK323X.lumilabs.oneplan'];
// Numeric App ID from App Store Connect. Env override first so dev/prod can
// diverge; the literal fallback is the live OnePlan app.
const APP_STORE_ID = process.env.APP_STORE_APP_APPLE_ID?.trim() || '6761648165';
const APP_STORE_URL = `https://apps.apple.com/app/id${APP_STORE_ID}`;

function buildAasaPayload(appIDs: string[]) {
  return {
    applinks: {
      details: [
        {
          appIDs,
          components: [
            { '/': '/friend/*', comment: 'Friend invites' },
            { '/': '/join/*', comment: 'Trip invites' },
            { '/': '/listing/*', comment: 'Marketplace listings' },
          ],
        },
      ],
    },
  };
}

function parseIosAppIds(config: ConfigService): string[] {
  const ids = (config.get<string>('IOS_APP_IDS') ?? '')
    .split(',')
    .map((id) => id.trim())
    .filter((id) => id.length > 0);
  return ids.length > 0 ? ids : DEFAULT_IOS_APP_IDS;
}

interface AndroidAppLinkTarget {
  packageName: string;
  fingerprints: string[];
}

function normalizeFingerprint(fingerprint: string): string {
  return fingerprint.trim().toUpperCase();
}

/**
 * dev and prod are separate Play apps with separate packages AND separate
 * signing certs, and each app can have multiple valid certs (Play app-signing
 * cert, upload cert, local debug cert for sideloaded QA builds). assetlinks.json
 * is an array of statements, so we parse into one target per package.
 *
 * Preferred config: ANDROID_APP_LINK_TARGETS, semicolon-separated app entries
 * of `package:fingerprint1,fingerprint2`, e.g.
 *   com.oneplan.android:AA:BB:...,CC:DD:...;com.oneplan.android.dev:EE:FF:...
 * Falls back to the legacy single-package ANDROID_APP_PACKAGE_NAME /
 * ANDROID_APP_SHA256_CERT_FINGERPRINTS pair when unset, for backward compat.
 */
function parseAndroidAppLinkTargets(
  config: ConfigService,
): AndroidAppLinkTarget[] {
  const raw = config.get<string>('ANDROID_APP_LINK_TARGETS')?.trim();
  if (raw) {
    return raw
      .split(';')
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0)
      .map((entry) => {
        const separatorIndex = entry.indexOf(':');
        const packageName =
          separatorIndex === -1
            ? entry.trim()
            : entry.slice(0, separatorIndex).trim();
        const fingerprints =
          separatorIndex === -1
            ? []
            : entry
                .slice(separatorIndex + 1)
                .split(',')
                .map(normalizeFingerprint)
                .filter((fp) => fp.length > 0);
        return { packageName, fingerprints };
      })
      .filter((target) => target.packageName.length > 0);
  }

  const legacyPackage =
    config.get<string>('ANDROID_APP_PACKAGE_NAME')?.trim() ||
    'com.oneplan.android';
  const legacyFingerprints = (
    config.get<string>('ANDROID_APP_SHA256_CERT_FINGERPRINTS') ?? ''
  )
    .split(',')
    .map(normalizeFingerprint)
    .filter((fp) => fp.length > 0);

  return [{ packageName: legacyPackage, fingerprints: legacyFingerprints }];
}

@ApiExcludeController()
@Public()
@SkipThrottle()
@Controller()
export class DeeplinksController {
  private readonly logger = new Logger(DeeplinksController.name);
  private readonly ogFriendImage: string;
  private readonly ogTripImage: string;
  private readonly androidAppLinkTargets: AndroidAppLinkTarget[];
  private readonly ogListingImage: string;
  private readonly aasaPayload: ReturnType<typeof buildAasaPayload>;

  constructor(
    private readonly tripsService: TripsService,
    private readonly friendsService: FriendsService,
    private readonly marketplaceService: MarketplaceService,
    config: ConfigService,
  ) {
    // R.4 / §6.11: Android App Links counterpart of the iOS AASA. Served on
    // the same hosts so a shared link / scanned QR opens the Android app
    // instead of the browser (matches the iOS Universal Links behavior).
    this.androidAppLinkTargets = parseAndroidAppLinkTargets(config);
    this.aasaPayload = buildAasaPayload(parseIosAppIds(config));
    const configuredTargets = this.androidAppLinkTargets.filter(
      (target) => target.fingerprints.length > 0,
    );
    if (configuredTargets.length === 0) {
      this.logger.warn(
        'ANDROID_APP_LINK_TARGETS (or legacy ANDROID_APP_SHA256_CERT_FINGERPRINTS) ' +
          'has no signing-cert fingerprints configured — Android App Links will NOT ' +
          'verify; /.well-known/assetlinks.json will serve an empty array.',
      );
    }

    // Public OG images live in the GCS public bucket. The bucket must have
    // `allUsers:objectViewer` granted at the IAM level so WhatsApp/iMessage/
    // etc. can fetch them without auth. Use the public bucket here, not
    // GCS_MEDIA_BUCKET — the latter is private and signed-URL only.
    const bucket = config.getOrThrow<string>('GCS_PUBLIC_BUCKET');
    const base = `https://storage.googleapis.com/${bucket}/og`;
    this.ogFriendImage = `${base}/og-friend.png`;
    this.ogTripImage = `${base}/og-trip.png`;
    this.ogListingImage = `${base}/og-listing.png`;
  }

  @Get('.well-known/apple-app-site-association')
  @Header('Content-Type', 'application/json')
  @Header('Cache-Control', 'public, max-age=3600')
  getAppleAppSiteAssociation() {
    return this.aasaPayload;
  }

  /**
   * R.4 / §6.11: Android Digital Asset Links — the counterpart of the iOS
   * AASA above, served on the same hosts (op.* / api.* / dev-*). The Android
   * App Links `autoVerify` flow fetches this to confirm the app may handle
   * https://{host}/join/*, /friend/*, and /listing/* without the browser.
   * One statement per configured package (dev + prod are separate Play apps
   * with separate signing certs), each carrying all its valid fingerprints.
   *
   * A package with no configured fingerprints is skipped — verification
   * fails closed (links render the landing page) rather than serving a
   * malformed statement. The constructor already logged a warning for this.
   */
  @Get('.well-known/assetlinks.json')
  @Header('Content-Type', 'application/json')
  @Header('Cache-Control', 'public, max-age=3600')
  getAndroidAssetLinks() {
    return this.androidAppLinkTargets
      .filter((target) => target.fingerprints.length > 0)
      .map((target) => ({
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: target.packageName,
          sha256_cert_fingerprints: target.fingerprints,
        },
      }));
  }

  @Get('friend/:friendCode')
  @Header('Content-Type', 'text/html; charset=utf-8')
  async friendLanding(
    @Param('friendCode') friendCode: string,
  ): Promise<string> {
    const safeCode = encodeURIComponent(friendCode);
    const customScheme = `oneplan://friend/${safeCode}`;

    let title = 'Join me on OnePlan';
    let description =
      'Someone invited you to connect on OnePlan. Install the app to accept.';

    try {
      const preview =
        await this.friendsService.getPublicPreviewByCode(friendCode);
      title = `Add ${preview.displayName} on OnePlan`;
      description = `${preview.displayName} has sent you a friend request.`;
    } catch {
      // Invalid / expired code → keep generic copy.
    }

    return renderLanding({
      title,
      description,
      ogImage: this.ogFriendImage,
      openInAppUrl: customScheme,
    });
  }

  @Get('join/:inviteCode')
  @Header('Content-Type', 'text/html; charset=utf-8')
  async joinLanding(@Param('inviteCode') inviteCode: string): Promise<string> {
    const safeCode = encodeURIComponent(inviteCode);
    const customScheme = `oneplan://join/${safeCode}`;

    let title = 'Join this trip on OnePlan';
    let description = "You've been invited to plan a trip together.";

    try {
      const preview = await this.tripsService.getInvitePreview(inviteCode);
      title = `Join "${preview.name}" on OnePlan`;
      description = `${preview.memberCount} traveler${preview.memberCount === 1 ? '' : 's'} on this trip. Tap to join.`;
    } catch {
      // Invalid / expired invite → fall through to the generic copy above.
    }

    return renderLanding({
      title,
      description,
      ogImage: this.ogTripImage,
      openInAppUrl: customScheme,
    });
  }

  @Get('listing/:id')
  @Header('Content-Type', 'text/html; charset=utf-8')
  async listingLanding(@Param('id') id: string): Promise<string> {
    const safeId = encodeURIComponent(id);
    const customScheme = `oneplan://listing/${safeId}`;

    let title = 'Check out this trip plan on OnePlan';
    let description =
      'A curated trip plan on OnePlan. Install the app to view and use it.';

    try {
      const preview = await this.marketplaceService.getPublicListingPreview(id);
      title = `${preview.name} on OnePlan`;
      description = `${preview.creatorName}'s ${preview.durationDays}-day plan. Tap to view on OnePlan.`;
    } catch {
      // Invalid / non-approved / deleted listing → keep generic copy.
    }

    return renderLanding({
      title,
      description,
      ogImage: this.ogListingImage,
      openInAppUrl: customScheme,
    });
  }
}

interface LandingParams {
  title: string;
  description: string;
  ogImage: string;
  openInAppUrl: string;
}

function renderLanding(params: LandingParams): string {
  const { title, description, ogImage, openInAppUrl } = params;
  const esc = escapeHtml;
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="apple-itunes-app" content="app-id=${APP_STORE_ID}">
<title>${esc(title)}</title>
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:image" content="${esc(ogImage)}">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(description)}">
<meta name="twitter:image" content="${esc(ogImage)}">
<style>
  :root { color-scheme: dark; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; margin: 0; padding: 0; background: #0a0a0b; color: #f5f5f7; min-height: 100vh; display: flex; align-items: center; justify-content: center; }
  .card { max-width: 420px; width: calc(100% - 32px); margin: 16px; padding: 32px 24px; background: #161618; border-radius: 24px; box-shadow: 0 12px 40px rgba(0,0,0,0.4); text-align: center; }
  .hero { width: 100%; max-width: 280px; height: auto; border-radius: 16px; margin: 0 auto 20px; display: block; }
  h1 { font-size: 22px; font-weight: 600; margin: 0 0 8px; letter-spacing: -0.4px; color: #ffffff; }
  p { font-size: 15px; line-height: 1.45; margin: 0 0 24px; color: rgba(255,255,255,0.7); }
  a.btn { display: block; padding: 14px 20px; border-radius: 14px; font-weight: 600; font-size: 16px; text-decoration: none; margin-bottom: 10px; }
  a.primary { background: #2563eb; color: #ffffff; }
  a.secondary { background: transparent; color: #ffffff; border: 1px solid rgba(255,255,255,0.25); }
</style>
</head>
<body>
  <main class="card">
    <img class="hero" src="${esc(ogImage)}" alt="">
    <h1>${esc(title)}</h1>
    <p>${esc(description)}</p>
    <a class="btn primary" id="openApp" href="${esc(openInAppUrl)}">Open in OnePlan</a>
    <a class="btn secondary" href="${APP_STORE_URL}">Get the app</a>
  </main>
  <script>
    // On iOS, tapping "Open in OnePlan" first attempts the custom scheme.
    // If the app isn't installed, the scheme is a no-op; the user can then
    // tap "Get the app". Universal Links make this button redundant for
    // installed users (iOS routes the original HTTPS URL straight to the app
    // before the landing page is even rendered), but it remains useful as a
    // manual retry if AASA propagation hasn't completed.
  </script>
</body>
</html>`;
}

function escapeHtml(input: string): string {
  return input
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
