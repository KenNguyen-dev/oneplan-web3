import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';
import { SocialTokenPayload } from './apple-auth.service';

@Injectable()
export class GoogleAuthService {
  private readonly client: OAuth2Client;
  private readonly audiences: string[];

  constructor(private readonly config: ConfigService) {
    const raw = this.config.getOrThrow<string>('GOOGLE_CLIENT_ID');
    this.audiences = raw
      .split(',')
      .map((id) => id.trim())
      .filter((id) => id.length > 0);
    this.client = new OAuth2Client(this.audiences[0]);
  }

  async verifyIdentityToken(
    identityToken: string,
  ): Promise<SocialTokenPayload> {
    const ticket = await this.client.verifyIdToken({
      idToken: identityToken,
      audience: this.audiences,
    });

    const payload = ticket.getPayload()!;

    return {
      sub: payload.sub,
      email: payload.email ?? null,
      emailVerified: payload.email_verified ?? false,
    };
  }
}
