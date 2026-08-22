import {
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GoogleAuth } from 'google-auth-library';

const ANDROID_PUBLISHER_BASE =
  'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';
const ANDROID_PUBLISHER_SCOPE =
  'https://www.googleapis.com/auth/androidpublisher';

/**
 * The kind of Google Play purchase being verified. Auto-renewing Pro SKUs are
 * subscriptions; one-time products (`pay_once`, marketplace listings) are
 * products.
 */
export type PlayPurchaseKind = 'subscription' | 'product';

// Android Publisher purchases.subscriptions.get (v1) response subset.
export type GooglePlaySubscriptionResponse = {
  startTimeMillis?: string;
  expiryTimeMillis?: string;
  orderId?: string;
  // 0: payment pending, 1: payment received, 2: free trial, 3: pending deferred
  paymentState?: number;
  // 0: yet to be acknowledged, 1: acknowledged
  acknowledgementState?: number;
  // Present and in the past when the user cancelled.
  userCancellationTimeMillis?: string;
  // 0: user, 1: system, 2: replaced, 3: developer
  cancelReason?: number;
  // 0 = Test (license tester), absent = Production
  purchaseType?: number;
  // The purchase token of the old subscription if this is an upgrade/downgrade.
  linkedPurchaseToken?: string;
};

// Android Publisher purchases.products.get response subset.
export type GooglePlayProductResponse = {
  orderId?: string;
  // 0: purchased, 1: cancelled, 2: pending
  purchaseState?: number;
  purchaseTimeMillis?: string;
  // 0: yet to be acknowledged, 1: acknowledged
  acknowledgementState?: number;
  // Only set when NOT a standard billing-flow purchase. 0: Test (license
  // tester account), 1: Promo, 2: Rewarded. Absent/undefined for a real purchase.
  purchaseType?: number;
};

/**
 * Single owner of the Google Play Android Publisher REST plumbing shared by the
 * subscription and marketplace verifiers: service-account access tokens, the
 * `purchases.{subscriptions,products}.{get,acknowledge}` calls, package
 * validation, the required-config guard and millis parsing.
 *
 * Both verifiers delegate here so the acknowledge-after-purchase contract
 * (Google auto-refunds an un-acknowledged purchase after 3 days) cannot drift
 * between them. Intentionally REST (no googleapis SDK) to keep the dependency
 * surface small. Entitlement policy (active/revoked) stays in each verifier.
 */
@Injectable()
export class GooglePlayPurchaseClient {
  private readonly logger = new Logger(GooglePlayPurchaseClient.name);

  constructor(private readonly config: ConfigService) {}

  /** True when Play Billing server credentials are configured. */
  isConfigured(): boolean {
    return (
      !!this.config.get<string>('GOOGLE_PLAY_PACKAGE_NAME')?.trim() &&
      !!this.config.get<string>('GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL')?.trim() &&
      !!this.config
        .get<string>('GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY')
        ?.trim()
    );
  }

  /** Configured package name; throws if Play Billing is not configured. */
  getPackageName(): string {
    return this.requiredConfig('GOOGLE_PLAY_PACKAGE_NAME');
  }

  /**
   * Validates the client-supplied package name against the configured one and
   * returns the configured package name for use in subsequent requests.
   */
  assertPackageMatches(dtoPackageName: string): string {
    const packageName = this.getPackageName();
    if (dtoPackageName !== packageName) {
      throw new BadRequestException(
        'Purchase package does not match server configuration',
      );
    }
    return packageName;
  }

  async acquireAccessToken(): Promise<string> {
    const clientEmail = this.requiredConfig(
      'GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL',
    );
    const privateKey = this.requiredConfig(
      'GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY',
    ).replace(/\\n/g, '\n');

    const auth = new GoogleAuth({
      credentials: { client_email: clientEmail, private_key: privateKey },
      scopes: [ANDROID_PUBLISHER_SCOPE],
    });
    const client = await auth.getClient();
    const accessTokenResult = await client.getAccessToken();
    const accessToken =
      typeof accessTokenResult === 'string'
        ? accessTokenResult
        : accessTokenResult?.token;

    if (!accessToken) {
      throw new ServiceUnavailableException(
        'Google Play purchase verification is not configured',
      );
    }
    return accessToken;
  }

  /** GET purchases.subscriptions — throws BadRequestException on not-found / failure. */
  async getSubscription(
    packageName: string,
    productId: string,
    purchaseToken: string,
    accessToken: string,
  ): Promise<GooglePlaySubscriptionResponse> {
    const response = await fetch(
      this.subscriptionBase(packageName, productId, purchaseToken),
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );
    this.assertGetOk(response, 'subscription');
    return (await response.json()) as GooglePlaySubscriptionResponse;
  }

  /** GET purchases.products — throws BadRequestException on not-found / failure. */
  async getProduct(
    packageName: string,
    productId: string,
    purchaseToken: string,
    accessToken: string,
  ): Promise<GooglePlayProductResponse> {
    const response = await fetch(
      this.productBase(packageName, productId, purchaseToken),
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );
    this.assertGetOk(response, 'purchase');
    return (await response.json()) as GooglePlayProductResponse;
  }

  acknowledgeSubscription(
    packageName: string,
    productId: string,
    purchaseToken: string,
    accessToken: string,
  ): Promise<boolean> {
    return this.acknowledge(
      `${this.subscriptionBase(packageName, productId, purchaseToken)}:acknowledge`,
      accessToken,
      'subscription',
    );
  }

  acknowledgeProduct(
    packageName: string,
    productId: string,
    purchaseToken: string,
    accessToken: string,
  ): Promise<boolean> {
    return this.acknowledge(
      `${this.productBase(packageName, productId, purchaseToken)}:acknowledge`,
      accessToken,
      'product',
    );
  }

  parseMillis(value?: string): Date | null {
    if (!value) return null;
    const millis = Number(value);
    if (!Number.isFinite(millis) || millis <= 0) {
      return null;
    }
    return new Date(millis);
  }

  private subscriptionBase(
    packageName: string,
    productId: string,
    purchaseToken: string,
  ): string {
    return (
      `${ANDROID_PUBLISHER_BASE}/${encodeURIComponent(packageName)}` +
      `/purchases/subscriptions/${encodeURIComponent(productId)}` +
      `/tokens/${encodeURIComponent(purchaseToken)}`
    );
  }

  private productBase(
    packageName: string,
    productId: string,
    purchaseToken: string,
  ): string {
    return (
      `${ANDROID_PUBLISHER_BASE}/${encodeURIComponent(packageName)}` +
      `/purchases/products/${encodeURIComponent(productId)}` +
      `/tokens/${encodeURIComponent(purchaseToken)}`
    );
  }

  private assertGetOk(response: Response, label: 'subscription' | 'purchase') {
    if (response.status === 404 || response.status === 410) {
      throw new BadRequestException(`Google Play ${label} not found`);
    }
    if (!response.ok) {
      this.logger.warn(
        `Google Play ${label} verification failed: ${response.status}`,
      );
      throw new BadRequestException(`Unable to verify Google Play ${label}`);
    }
  }

  /**
   * Acknowledges the purchase. Best-effort: Google treats a second
   * acknowledgement of an already-acknowledged token as a 400, which we treat
   * as success; a transient failure should not block granting an
   * otherwise-valid entitlement (a later verify call retries). Returns whether
   * the purchase is acknowledged.
   */
  private async acknowledge(
    url: string,
    accessToken: string,
    kind: PlayPurchaseKind,
  ): Promise<boolean> {
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: '{}',
      });
      if (response.ok) {
        return true;
      }
      // 400 here typically means "already acknowledged" — treat as success.
      if (response.status === 400) {
        return true;
      }
      this.logger.warn(
        `Failed to acknowledge Google Play ${kind}: ${response.status}`,
      );
      return false;
    } catch (error) {
      this.logger.warn(
        `Error acknowledging Google Play ${kind}`,
        error as Error,
      );
      return false;
    }
  }

  private requiredConfig(key: string): string {
    const value = this.config.get<string>(key)?.trim();
    if (!value) {
      throw new ServiceUnavailableException(
        'Google Play purchase verification is not configured',
      );
    }
    return value;
  }
}
