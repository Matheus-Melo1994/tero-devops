import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
import { writeLog } from '../logger';

@Injectable()
export class LoggerMiddleware implements NestMiddleware {
  use(request: Request, response: Response, next: NextFunction) {
    const startAt = process.hrtime.bigint();
    const supplied = request.get('x-request-id');
    const requestId = supplied && /^[A-Za-z0-9_-]{1,64}$/.test(supplied) ? supplied : undefined;

    response.on('finish', () => {
      writeLog(response.statusCode >= 500 ? 'error' : 'log', 'HTTP request', {
        method: request.method,
        route: request.route?.path || 'unmatched',
        status: response.statusCode,
        duration_ms: Number(process.hrtime.bigint() - startAt) / 1e6,
        ...(requestId ? { request_id: requestId } : {}),
      });
    });

    next();
  }
}
