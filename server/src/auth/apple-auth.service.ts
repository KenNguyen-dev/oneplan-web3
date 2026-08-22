import {
  Injectable,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'crypto';
import { createRemoteJWKSet, jwtVerify } from 'jose';

export interface SocialTokenPayload {
  sub: string;
  email: string | null;
  emailVerified: boolean;
}

@Injectable()
export class AppleAuthService implements OnModuleInit {
  private jwks!: ReturnType<typeof createRemoteJWKSet>;
  private readonly audiences: string[];

  constructor(private readonly config: ConfigService) {
    // Apple ID tokens carry a single `aud` claim equal to the OAuth client id
    // they were issued for. iOS uses the bundle identifier — the app ships in
    // three flavors (local./dev./bare lumilabs.oneplan), so APPLE_CLIENT_ID
    // accepts a comma-separated list. The web Sign in with Apple flow uses a
    // separate Services ID (APPLE_WEB_CLIENT_ID). `jose` accepts an array and
    // matches if the token's `aud` equals any entry — there's no
    // cross-audience leakage.
    const ios = this.config.getOrThrow<string>('APPLE_CLIENT_ID');
    const web = this.config.get<string>('APPLE_WEB_CLIENT_ID') ?? '';
    this.audiences = [...ios.split(','), web]
      .map((a) => a.trim())
      .filter((a) => a.length > 0);
  }

  onModuleInit() {
    this.jwks = createRemoteJWKSet(
      new URL('https://appleid.apple.com/auth/keys'),
    );
  }

  async verifyIdentityToken(
    identityToken: string,
    rawNonce?: string,
  ): Promise<SocialTokenPayload> {
    const { payload } = await jwtVerify(identityToken, this.jwks, {
      issuer: 'https://appleid.apple.com',
      audience: this.audiences,
    });

    if (rawNonce !== undefined) {
      // The client sets request.nonce = sha256Hex(rawNonce); Apple echoes that
      // hash back in the JWT's `nonce` claim. Compare hex-encoded SHA-256.
      const expected = createHash('sha256').update(rawNonce).digest('hex');
      const actual =
        typeof payload['nonce'] === 'string' ? payload['nonce'] : '';
      if (actual !== expected) {
        throw new UnauthorizedException('Apple Sign-In nonce mismatch');
      }
    }

    return {
      sub: payload.sub!,
      email: (payload['email'] as string) ?? null,
      emailVerified:
        payload['email_verified'] === true ||
        payload['email_verified'] === 'true',
    };
  }
}
