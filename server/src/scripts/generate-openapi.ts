import { NestFactory } from '@nestjs/core';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { AppModule } from '../app.module';

async function generate() {
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter(),
    { logger: false },
  );

  const config = new DocumentBuilder()
    .setTitle('OnePlan API')
    .setDescription('Backend API for the OnePlan travel planning app')
    .setVersion('0.1.0')
    .addServer('http://localhost:3000', 'Local development')
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, config);

  // Script is always invoked from server/ via npm script
  const outDir = join(process.cwd(), '..', 'openapi');
  mkdirSync(outDir, { recursive: true });

  const outPath = join(outDir, 'openapi.json');
  writeFileSync(outPath, JSON.stringify(document, null, 2));

  console.log(`OpenAPI spec written to ${outPath}`);
  await app.close();
  process.exit(0);
}

generate();
