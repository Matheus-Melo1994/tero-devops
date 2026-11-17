import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { JsonLogger, writeLog } from './logger';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { logger: new JsonLogger() });
  app.useGlobalPipes(new ValidationPipe());
  app.enableShutdownHooks();

  const port = process.env.PORT || 8080;
  await app.listen(port);
}
bootstrap().catch((error: unknown) => {
  writeLog('fatal', 'Checkout startup failed', { error_type: error instanceof Error ? error.name : 'unknown' });
  process.exitCode = 1;
});
