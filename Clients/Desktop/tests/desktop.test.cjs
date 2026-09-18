const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { _electron: electron } = require('playwright');

test('real desktop and engine save availability, survive restart and close cleanly', { skip: !process.env.Q_ENGINE_PATH, timeout: 60000 }, async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'q-desktop-test-'));
  const results = path.resolve(__dirname, '../test-results');
  await fs.mkdir(results, { recursive: true });
  let app;
  const launch = () => electron.launch({
    args: [path.resolve(__dirname, '..')],
    env: { ...process.env, Q_DESKTOP_DATA: directory, Q_ENGINE_PORT: process.platform === 'win32' ? 'COM999' : '/dev/q-test-no-device' }
  });
  try {
    app = await launch();
    let page = await app.firstWindow();
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.getByRole('button', { name: 'Busy / DND', exact: false }).click();
    await page.waitForFunction(() => document.querySelector('#state-name').textContent === 'Busy / DND');
    await page.locator('#brightness').fill('42');
    await page.waitForFunction(() => document.querySelector('#brightness-value').value === '42%');
    // Wait for the acknowledgement from the engine, not optimistic renderer state.
    await page.evaluate(async () => {
      const deadline = Date.now() + 10000;
      while (Date.now() < deadline) {
        if ((await window.q.snapshot()).brightness === .42) return;
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      throw new Error('Engine did not acknowledge saved brightness');
    });
    const stored = JSON.parse(await fs.readFile(path.join(directory, 'settings.json'), 'utf8'));
    assert.equal(stored.stateID, 'busy'); assert.equal(stored.brightness, .42);
    assert.equal(await page.evaluate(() => typeof window.require), 'undefined');
    await page.screenshot({ path: path.join(results, 'availability.png') });
    await page.getByRole('button', { name: 'Settings' }).click();
    await page.getByRole('heading', { name: 'Your Q' }).waitFor();
    await page.screenshot({ path: path.join(results, 'settings.png') });
    let closed = app.waitForEvent('close');
    await page.getByRole('button', { name: 'Quit Q', exact: true }).click();
    await closed; app = undefined;
    app = await launch(); page = await app.firstWindow();
    await page.waitForFunction(() => document.querySelector('#state-name').textContent === 'Busy / DND');
    assert.equal(await page.locator('#brightness').inputValue(), '42');
    assert.deepEqual(errors, []);
    await page.getByRole('button', { name: 'Switch to Available' }).click();
    await page.waitForFunction(() => document.querySelector('#state-name').textContent === 'Available');
    closed = app.waitForEvent('close');
    await page.getByRole('button', { name: 'Quit Q', exact: true }).click();
    await closed; app = undefined;
  } finally {
    if (app) await app.close();
    await fs.rm(directory, { recursive: true, force: true });
  }
});
