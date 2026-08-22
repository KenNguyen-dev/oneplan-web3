import { registerAs } from '@nestjs/config';

function parseList(raw: string | undefined): string[] {
  if (!raw) return [];
  return raw
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
}

export interface AdminConfig {
  emails: string[];
  webOrigins: string[];
}

export const adminConfig = registerAs<AdminConfig>('admin', () => ({
  emails: parseList(process.env.ADMIN_EMAILS).map((email) =>
    email.toLowerCase(),
  ),
  webOrigins: parseList(process.env.ADMIN_WEB_ORIGINS),
}));
