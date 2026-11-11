import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

const baseUrl = (process.env.TERO_BASE_URL || 'http://localhost:8080').replace(/\/+$/, '');
const requestTimeoutMs = Number(process.env.TERO_REQUEST_TIMEOUT_MS || 10000);
const readyTimeoutMs = Number(process.env.TERO_READY_TIMEOUT_MS || 90000);
assert.ok(Number.isSafeInteger(requestTimeoutMs) && requestTimeoutMs > 0,
  'TERO_REQUEST_TIMEOUT_MS debe ser un entero positivo en milisegundos');
assert.ok(Number.isSafeInteger(readyTimeoutMs) && readyTimeoutMs > 0,
  'TERO_READY_TIMEOUT_MS debe ser un entero positivo en milisegundos');
assert.ok(['http:', 'https:'].includes(new URL(baseUrl).protocol),
  'TERO_BASE_URL debe ser una URL HTTP o HTTPS de la UI');

// Se prueba el stack real a través de la UI, con timeout por petición y sin reintentos
// de escrituras: repetir submit ante un fallo de red podría crear otra orden.
async function request(path, {
  method = 'GET', body, status = 200, json = true, timeoutMs = requestTimeoutMs,
} = {}) {
  let response;
  let text;
  try {
    response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: body === undefined ? {} : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    text = await response.text();
  } catch (cause) {
    throw new Error(`${method} ${path} falló contra ${baseUrl}. Verificar que Tero esté levantado.`,
      { cause });
  }
  assert.equal(response.status, status,
    `${method} ${path}: HTTP esperado ${status}, recibido ${response.status}. ${text.slice(0, 300)}`);
  return text.length ? (json ? JSON.parse(text) : text) : null;
}

// Compose puede iniciar la UI antes de que sus dependencias acepten peticiones.
// Solo estas lecturas de disponibilidad se reintentan; no las pruebas funcionales.
before(async () => {
  const deadline = Date.now() + readyTimeoutMs;
  const readinessId = `integration-readiness-${randomUUID()}`;
  const checks = [
    { path: '/health', json: false },
    { path: '/api/catalog/products' },
    { path: '/api/orders' },
    { path: `/api/carts/${readinessId}` },
    { path: `/api/checkout/${readinessId}`, status: 404 },
  ];
  let lastError;
  while (Date.now() < deadline) {
    try {
      for (const { path, ...options } of checks) {
        const remainingMs = deadline - Date.now();
        if (remainingMs <= 0) throw new Error('Se agotó la espera de disponibilidad');
        await request(path, { ...options, timeoutMs: Math.min(requestTimeoutMs, remainingMs) });
      }
      return;
    } catch (error) {
      lastError = error;
      const remainingMs = deadline - Date.now();
      if (remainingMs > 0) await delay(Math.min(1000, remainingMs));
    }
  }
  throw new Error(`Tero no estuvo disponible en ${baseUrl} durante ${readyTimeoutMs} ms: ${lastError?.message}`,
    { cause: lastError });
});

async function catalogProduct() {
  const products = await request('/api/catalog/products');
  assert.ok(Array.isArray(products) && products.length > 0,
    'El catálogo debe tener al menos un producto de los datos iniciales');
  const product = products[0];
  assert.ok(typeof product.id === 'string' && product.id.length > 0);
  assert.ok(typeof product.name === 'string' && product.name.length > 0);
  assert.ok(Number.isSafeInteger(product.price) && product.price >= 0,
    'El precio del catálogo debe ser un entero no negativo');
  return product;
}

async function withIsolatedCart(t, run) {
  const customerId = `integration-${randomUUID()}`;
  const cartPath = `/api/carts/${encodeURIComponent(customerId)}`;
  let testFailed = false;
  t.diagnostic(`Cliente de prueba: ${customerId}`);
  try {
    await run({ customerId, cartPath });
  } catch (error) {
    testFailed = true;
    throw error;
  } finally {
    // Solo se eliminan datos del UUID creado por este caso; jamás carritos ajenos.
    try {
      await request(cartPath, { method: 'DELETE', status: 202 });
    } catch (error) {
      if (!testFailed) throw error;
      t.diagnostic(`También falló la limpieza de ${customerId}: ${error.message}`);
    }
  }
}

test('catálogo → carrito: agregar, recuperar y quitar un producto', async (t) => {
  await withIsolatedCart(t, async ({ customerId, cartPath }) => {
    const product = await catalogProduct();
    const detail = await request(`/api/catalog/products/${encodeURIComponent(product.id)}`);
    assert.equal(detail.id, product.id);
    assert.equal(detail.name, product.name);
    assert.equal(detail.price, product.price);

    const item = { itemId: product.id, quantity: 2, unitPrice: product.price };
    const added = await request(`${cartPath}/items`, { method: 'POST', body: item, status: 201 });
    assert.deepEqual(added, item);

    const cart = await request(cartPath);
    assert.equal(cart.customerId, customerId);
    assert.deepEqual(cart.items, [item], 'El carrito debe conservar cantidad y precio');
    const itemPath = `${cartPath}/items/${encodeURIComponent(product.id)}`;
    assert.deepEqual(await request(itemPath), item);

    await request(itemPath, { method: 'DELETE', status: 202 });
    await request(itemPath, { status: 404 });
    assert.deepEqual((await request(cartPath)).items, [], 'El producto debe desaparecer del carrito');
  });
});

test('compra → orden: persistir la compra, eliminar la sesión y vaciar el carrito', async (t) => {
  await withIsolatedCart(t, async ({ customerId, cartPath }) => {
    const product = await catalogProduct();
    const cartItem = { itemId: product.id, quantity: 2, unitPrice: product.price };
    await request(`${cartPath}/items`, { method: 'POST', body: cartItem, status: 201 });
    const cart = await request(cartPath);
    assert.equal(cart.customerId, customerId);
    assert.deepEqual(cart.items, [cartItem]);

    // El navegador transforma los datos del carrito al contrato de Checkout.
    const items = cart.items.map((item) => ({
      id: item.itemId,
      name: product.name,
      quantity: item.quantity,
      price: item.unitPrice,
    }));
    const expectedItems = items.map((item) => ({ ...item, totalCost: item.price * item.quantity }));
    const shippingAddress = {
      firstName: 'Integracion',
      lastName: 'Tero',
      email: `${customerId}@example.test`,
      address1: 'Direccion de prueba 123',
      address2: '',
      city: 'Montevideo',
      state: 'Montevideo',
      zip: '11000',
    };
    const checkoutPath = `/api/checkout/${encodeURIComponent(customerId)}`;
    let sessionMayRemain = false;
    try {
      // Se marca antes de escribir: un timeout puede ocurrir después de persistir.
      sessionMayRemain = true;
      const checkout = await request(`${checkoutPath}/update`, {
        method: 'POST', status: 201,
        body: { items, shippingAddress, deliveryOptionToken: 'priority-mail' },
      });
      const subtotal = product.price * cartItem.quantity;
      // Contrato actual: importes enteros, envío priority-mail=10 e impuesto=5.
      assert.equal(checkout.subtotal, subtotal);
      assert.equal(checkout.shipping, 10);
      assert.equal(checkout.tax, 5);
      assert.equal(checkout.total, subtotal + 15);
      assert.deepEqual(checkout.items, expectedItems);
      assert.deepEqual(checkout.shippingAddress, shippingAddress);
      assert.deepEqual(await request(checkoutPath), checkout,
        'La sesión debe poder recuperarse antes de confirmar la compra');

      const submitted = await request(`${checkoutPath}/submit`, { method: 'POST', status: 201 });
      assert.match(submitted.orderId, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
      t.diagnostic(`Orden sintética conservada: ${submitted.orderId}; email: ${shippingAddress.email}`);
      assert.equal(submitted.email, shippingAddress.email);
      assert.deepEqual(submitted.items, expectedItems);
      for (const field of ['subtotal', 'shipping', 'tax', 'total']) {
        assert.equal(submitted[field], checkout[field], `La confirmación debe conservar ${field}`);
      }

      await request(checkoutPath, { status: 404 });
      sessionMayRemain = false;

      // Orders solo expone listado: buscar exclusivamente la orden recién creada.
      const orders = await request('/api/orders');
      assert.ok(Array.isArray(orders), 'Orders debe devolver una lista');
      const matches = orders.filter((order) => order.id === submitted.orderId);
      assert.equal(matches.length, 1, 'Debe existir exactamente una orden con el ID confirmado');
      const order = matches[0];
      for (const field of ['firstName', 'lastName', 'email', 'address1', 'address2', 'city', 'state']) {
        assert.equal(order[field], shippingAddress[field], `La orden debe conservar ${field}`);
      }
      assert.equal(order.zipCode, shippingAddress.zip);
      assert.ok(Number.isFinite(Date.parse(order.createdDate)), 'La orden debe tener fecha válida');
      assert.deepEqual(order.items, expectedItems.map(({ id, ...item }) => ({ productId: id, ...item })),
        'Orders debe conservar producto, cantidad, precio unitario y total por artículo');

      // Checkout elimina su sesión; el cliente es responsable de vaciar Cart.
      await request(cartPath, { method: 'DELETE', status: 202 });
      assert.deepEqual((await request(cartPath)).items, [], 'El carrito debe quedar vacío');
    } finally {
      if (sessionMayRemain) {
        t.diagnostic(`Puede quedar una sesión de checkout con clave ${customerId}. No hay API de borrado; no se reintenta submit para limpiarla.`);
      }
    }
    // No hay API para borrar órdenes. Se conserva la orden sintética como evidencia.
  });
});
