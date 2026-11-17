import { LoggerService } from '@nestjs/common';

type Level = 'log' | 'error' | 'warn' | 'debug' | 'verbose' | 'fatal';

export function writeLog(level: Level, message: string, fields: Record<string, unknown> = {}): void {
  const line = JSON.stringify({ timestamp: new Date().toISOString(), service: 'checkout', level: level === 'log' ? 'info' : level, message, ...fields });
  (level === 'error' || level === 'fatal' ? process.stderr : process.stdout).write(line + '\n');
}

process.removeAllListeners('warning');
process.on('warning', (warning) => writeLog('warn', 'Runtime warning', {
  warning_type: warning.name,
  ...('code' in warning && typeof warning.code === 'string' ? { code: warning.code } : {}),
}));

export class JsonLogger implements LoggerService {
  log(message: unknown, ...params: unknown[]): void { this.emit('log', message, params); }
  error(message: unknown, ...params: unknown[]): void { this.emit('error', message, params); }
  warn(message: unknown, ...params: unknown[]): void { this.emit('warn', message, params); }
  debug(message: unknown, ...params: unknown[]): void { this.emit('debug', message, params); }
  verbose(message: unknown, ...params: unknown[]): void { this.emit('verbose', message, params); }
  fatal(message: unknown, ...params: unknown[]): void { this.emit('fatal', message, params); }

  private emit(level: Level, value: unknown, params: unknown[]): void {
    const message = typeof value === 'string' ? value : 'Application error';
    const context = params.find((param) => typeof param === 'string');
    writeLog(level, message, context ? { context } : {});
  }
}
