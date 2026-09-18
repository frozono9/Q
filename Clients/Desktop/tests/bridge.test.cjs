const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateCommand } = require('../bridge.cjs');
test('renderer cannot invoke shell commands, arbitrary states or invalid brightness', () => {
  for (const value of [null, {}, { operation: 'exec', command: 'anything' }, { operation: 'setState', stateID: '../busy' },
    { operation: 'setBrightness', brightness: NaN }, { operation: 'setBrightness', brightness: 0 }, { operation: 'setBrightness', brightness: '0.5' }]) {
    assert.throws(() => validateCommand(value));
  }
  assert.deepEqual(validateCommand({ operation: 'press', command: 'ignored' }), { operation: 'press' });
});
