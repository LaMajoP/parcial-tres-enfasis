import { expect, test } from '@playwright/test';
test('muestra ambiente, disponibilidad, flags y permite iniciar una sesión', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Control de recarga confiable' })).toBeVisible();
  await expect(page.getByText('Disponibilidad de conectores')).toBeVisible();
  await expect(page.getByText('ENABLE_DYNAMIC_SURGE_PRICING')).toBeVisible();
  await page.getByRole('button', { name: 'Confirmar reserva y carga' }).click();
  await expect(page.getByText(/COMPLETED|COMPENSATED|COMPENSATION_FAILED/).first()).toBeVisible({ timeout: 12_000 });
  await expect(page.getByText('Sesión seleccionada')).toBeVisible();
});
