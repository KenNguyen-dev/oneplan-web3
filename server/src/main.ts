import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import { WsAdapter } from '@nestjs/platform-ws';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import multipart from '@fastify/multipart';
import cors from '@fastify/cors';
import { AppModule } from './app.module';

/**
 * Keeps a stray rejected promise from taking the API down with it.
 *
 * Node exits the process on an unhandled rejection. That is the right default
 * for a script and the wrong one for a server: a rate-limited background read
 * of a Solana account killed the API for every client, twice, and each device
 * reported itself as offline over something no user had asked for.
 *
 * This logs rather than swallows, and deliberately logs the whole error: an
 * unhandled rejection has no call site in our own stack, so the text is the
 * only thing that says where it came from. Anything that is genuinely ours to
 * handle should still be caught where it happens — this is the floor, not the
 * plan.
 */
function keepAliveOnUnhandledRejection(): void {
  process.on('unhandledRejection', (reason) => {
    const logger = new Logger('UnhandledRejection');
    logger.error(reason instanceof Error ? reason.stack : String(reason));
  });
}

async function bootstrap() {
  keepAliveOnUnhandledRejection();
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter(),
  );

  const parseOrigins = (raw: string | undefined): string[] =>
    (raw ?? '')
      .split(',')
      .map((origin) => origin.trim())
      .filter((origin) => origin.length > 0);

  const mergedOrigins = Array.from(
    new Set([
      ...parseOrigins(process.env.DASHBOARD_WEB_ORIGINS),
      ...parseOrigins(process.env.ADMIN_WEB_ORIGINS),
    ]),
  );

  await app.register(cors, {
    // origin:[] would block every cross-origin request silently. Falling back
    // to false disables CORS (same-origin only) — fail-closed but visible.
    origin: mergedOrigins.length > 0 ? mergedOrigins : false,
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    credentials: true,
  });

  await app.register(multipart, {
    limits: { fileSize: 10 * 1024 * 1024 },
  });

  app.useWebSocketAdapter(new WsAdapter(app));

  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));

  // Run module lifecycle shutdown hooks (onModuleDestroy) on SIGTERM/SIGINT so
  // the Telegram long-poll loop stops cleanly on a prod redeploy — otherwise a
  // lingering poller collides with the new one (Telegram 409 Conflict).
  app.enableShutdownHooks();

  if (process.env.NODE_ENV !== 'production') {
    const config = new DocumentBuilder()
      .setTitle('OnePlan API')
      .setDescription('Backend API for the OnePlan travel planning app')
      .setVersion('0.1.0')
      .addServer('http://localhost:3000', 'Local development')
      .addBearerAuth()
      .build();

    const document = SwaggerModule.createDocument(app, config);
    SwaggerModule.setup('docs', app, document, {
      jsonDocumentUrl: 'docs/json',
      yamlDocumentUrl: 'docs/yaml',
    });
  }

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port, '0.0.0.0');
}
bootstrap();
