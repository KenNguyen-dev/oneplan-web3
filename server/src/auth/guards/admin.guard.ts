import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtPayload } from '../decorators/current-user.decorator';

@Injectable()
export class AdminGuard implements CanActivate {
  constructor(private readonly configService: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<{ user?: JwtPayload }>();
    const user = request.user;

    if (!user?.email) {
      throw new UnauthorizedException('Authentication required');
    }

    const adminEmails = this.configService.get<string[]>('admin.emails') ?? [];
    if (!adminEmails.includes(user.email.toLowerCase())) {
      throw new ForbiddenException('Admin access required');
    }
    return true;
  }
}
