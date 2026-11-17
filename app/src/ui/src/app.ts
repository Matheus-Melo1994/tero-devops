import express from 'express';
import path from 'path';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { accessLog, log } from './logger';

const app = express();
app.use(accessLog);

const CATALOG_URL  = process.env.RETAIL_UI_ENDPOINTS_CATALOG  || 'http://catalog:8080';
const CARTS_URL    = process.env.RETAIL_UI_ENDPOINTS_CARTS    || 'http://carts:8080';
const CHECKOUT_URL = process.env.RETAIL_UI_ENDPOINTS_CHECKOUT || 'http://checkout:8080';
const ORDERS_URL   = process.env.RETAIL_UI_ENDPOINTS_ORDERS   || 'http://orders:8080';

// Express strips the mount path before the proxy sees it.
// pathRewrite re-adds the service prefix, stripping trailing slash on bare paths.
const rewrite = (prefix: string) => (p: string) => prefix + (p === '/' ? '' : p);
const proxy = (target: string, prefix: string) => createProxyMiddleware({
  target,
  changeOrigin: true,
  pathRewrite: rewrite(prefix),
  on: {
    error: (_error, _request, response) => {
      log('error', 'Upstream request failed', { upstream: prefix });
      if ('writeHead' in response) response.writeHead(502);
      response.end();
    },
  },
});

app.use('/api/catalog',  proxy(CATALOG_URL, '/catalog'));
app.use('/api/carts',    proxy(CARTS_URL, '/carts'));
app.use('/api/checkout', proxy(CHECKOUT_URL, '/checkout'));
app.use('/api/orders',   proxy(ORDERS_URL, '/orders'));

app.use(express.static(path.join(__dirname, '../public')));

app.get('/health', (_req, res) => res.send('OK'));

app.use((error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  log('error', 'Unhandled request error', { error_type: error instanceof Error ? error.name : 'unknown' });
  res.status(500).send('Internal Server Error');
});

const port = parseInt(process.env.PORT || '8080', 10);
app.listen(port, () => log('info', 'UI listening', { port }));
