import { Request, Response, NextFunction } from 'express';

const service = 'ui';
type Level = 'info' | 'warn' | 'error';

export function log(level: Level, message: string, fields: Record<string, unknown> = {}): void {
  const line = JSON.stringify({ timestamp: new Date().toISOString(), service, level, message, ...fields });
  (level === 'error' ? process.stderr : process.stdout).write(line + '\n');
}

process.removeAllListeners('warning');
process.on('warning', (warning) => log('warn', 'Runtime warning', {
  warning_type: warning.name,
  ...('code' in warning && typeof warning.code === 'string' ? { code: warning.code } : {}),
}));

export function accessLog(req: Request, res: Response, next: NextFunction): void {
  const start = process.hrtime.bigint();
  const supplied = req.get('x-request-id');
  const requestId = supplied && /^[A-Za-z0-9_-]{1,64}$/.test(supplied) ? supplied : undefined;
  const route = /^\/api\/(catalog|carts|checkout|orders)(?:\/|$)/.exec(req.originalUrl)?.[0].replace(/\/$/, '')
    || (req.originalUrl === '/health' ? '/health' : 'static');
  res.on('finish', () => {
    log(res.statusCode >= 500 ? 'error' : 'info', 'HTTP request', {
      method: req.method,
      route,
      status: res.statusCode,
      duration_ms: Number(process.hrtime.bigint() - start) / 1e6,
      ...(requestId ? { request_id: requestId } : {}),
    });
  });
  next();
}
