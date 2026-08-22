import {
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { GooglePlayPurchaseClient } from '../google-play/google-play-purchase-client';
import { PurchaseMarketplaceListingDto } from './dto/purchase-marketplace-listing.dto';

type PurchaseVerificationListing = {
  id: number;
  playProductId: string | null;
};

export type VerifiedGooglePlayPurchase = {
  packageName: string;
  productId: string;
  purchaseToken: string;
  orderId: string | null;
  purchaseTime: Date | null;
};

@Injectable()
export class MarketplacePurchaseVerifierService {
  private readonly logger = new Logger(MarketplacePurchaseVerifierService.name);

  constructor(private readonly play: GooglePlayPurchaseClient) {}

  async verifyGooglePlayPurchase(
    listing: PurchaseVerificationListing,
    dto: PurchaseMarketplaceListingDto,
  ): Promise<VerifiedGooglePlayPurchase> {
    if (!listing.playProductId) {
      throw new BadRequestException(
        'Listing is not configured for Google Play purchase',
      );
    }

    if (dto.productId !== listing.playProductId) {
      throw new BadRequestException(
        'Purchase product does not match listing configuration',
      );
    }

    const packageName = this.play.assertPackageMatches(dto.packageName);
    const accessToken = await this.play.acquireAccessToken();

    const purchase = await this.play.getProduct(
      packageName,
      dto.productId,
      dto.purchaseToken,
      accessToken,
    );

    // purchaseState: 0 = purchased, 1 = cancelled, 2 = pending.
    if (purchase.purchaseState !== 0) {
      throw new BadRequestException('Google Play purchase is not completed');
    }

    // Acknowledge so Google does not auto-refund the purchase after 3 days.
    // Mirrors the subscription verifier; a 400 ("already acknowledged") is
    // treated as success inside the shared client.
    if (purchase.acknowledgementState !== 1) {
      const acknowledged = await this.play.acknowledgeProduct(
        packageName,
        dto.productId,
        dto.purchaseToken,
        accessToken,
      );
      if (!acknowledged) {
        // Fail closed: an un-acknowledged purchase is auto-refunded by Google
        // after 3 days, so we must NOT grant a durable acquisition. Surface a
        // retryable error so the client re-verifies and Google eventually
        // receives the acknowledgement (mirrors the subscription contract).
        this.logger.warn(
          `Google Play acknowledgement failed for listing ${listing.id}`,
        );
        throw new ServiceUnavailableException(
          'Purchase verified but could not be acknowledged; please try again',
        );
      }
    }

    return {
      packageName,
      productId: dto.productId,
      purchaseToken: dto.purchaseToken,
      orderId: purchase.orderId ?? dto.orderId ?? null,
      purchaseTime: this.play.parseMillis(
        purchase.purchaseTimeMillis ?? dto.purchaseTimeMillis,
      ),
    };
  }
}
