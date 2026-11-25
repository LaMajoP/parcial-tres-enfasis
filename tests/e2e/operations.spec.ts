import { expect, test } from '@playwright/test';
import { randomUUID } from 'node:crypto';

test('muestra ambiente, disponibilidad, flags y permite iniciar una sesión', async ({ page }) => {
  const fleetId = `e2e-${randomUUID()}`;
  const billing = process.env.BILLING_SERVICE_URL ?? 'http://localhost:3002';
  const gateway = process.env.GRAPHQL_URL ?? 'http://localhost:4000/graphql';
  let sagaId: string | undefined;
  const seeded = await page.request.post(`${billing}/seed`, { data: { fleetId, balanceCents: 500_000 } });
  expect(seeded.ok()).toBe(true);
  try {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Control de recarga confiable' })).toBeVisible();
    await expect(page.getByText('Disponibilidad de conectores')).toBeVisible();
    await expect(page.getByText('ENABLE_DYNAMIC_SURGE_PRICING')).toBeVisible();
    await page.getByLabel('Flota').fill(fleetId);
    await expect(page.getByLabel('Conector')).toHaveValue(/connector-/);
    await page.getByRole('button', { name: 'Confirmar reserva y carga' }).click();
    const resultPanel = page.locator('.two-columns .panel').nth(1);
    await expect(resultPanel.locator('code')).toBeVisible({ timeout: 20_000 });
    sagaId = (await resultPanel.locator('code').textContent())?.trim();
    expect(sagaId).toBeTruthy();
    await expect(resultPanel.getByText('COMPLETED')).toBeVisible();
    await expect(page.getByText('Sesión seleccionada')).toBeVisible();
  } finally {
    if (sagaId) {
      const closed = await page.request.post(gateway, { headers: { 'x-aegisvolt-role': 'admin-demo' }, data: { query: 'mutation Close($id:ID!){ closeCharging(sagaId:$id){ state } }', variables: { id: sagaId } } });
      expect(closed.ok()).toBe(true);
    }
  }
});
