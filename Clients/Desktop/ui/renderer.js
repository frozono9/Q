const $ = id => document.getElementById(id);
let snapshot = {}, settings = false, built = false, gestureTimer, lastGesture = 0;
const messages = { available: 'Open to a conversation.', focus: 'Time for uninterrupted work.', busy: 'Please do not disturb.', away: 'Stepping away for a while.', offline: 'No active signal.' };
const gestureNames = { singlePress: 'Single press', doublePress: 'Double press', triplePress: 'Triple press', longPress: 'Long press', longPressEnded: 'Long press released' };
function problem(message) { $('error').textContent = message; $('error').hidden = !message; }
async function send(command) { try { await window.q.command(command); } catch (error) { problem(error.message); } }
function render(value) {
  snapshot = value;
  problem(value.problem || value.error || '');
  $('connection').textContent = value.connected ? 'Q connected' : 'No Q';
  $('connection').classList.toggle('online', !!value.connected);
  $('state-name').textContent = value.stateName || 'Available';
  $('state-detail').textContent = messages[value.stateID] || 'Your status, at a glance.';
  const next = { available: 'Focus', focus: 'Busy / DND', busy: 'Available', away: 'Available', offline: 'Available' }[value.stateID] || 'Focus';
  $('action-name').textContent = `Switch to ${next}`;
  $('press').disabled = !value.states;
  $('brightness').disabled = !value.states;
  if (document.activeElement !== $('brightness')) $('brightness').value = Math.round((value.brightness ?? .85) * 100);
  $('brightness-value').value = `${$('brightness').value}%`;
  if (!built && value.states) {
    for (const state of value.states) {
      const button = document.createElement('button'); button.className = 'state'; button.dataset.state = state.id;
      const dot = document.createElement('span'); dot.className = 'state-dot'; dot.style.backgroundColor = state.id === 'offline' ? '#92959e' : state.color;
      const name = document.createElement('span'); name.textContent = state.name;
      const check = document.createElement('span'); check.className = 'check'; check.setAttribute('aria-hidden', 'true');
      button.append(dot, name, check); button.onclick = () => send({ operation: 'setState', stateID: state.id }); $('states').append(button);
    }
    built = true;
  }
  document.querySelectorAll('.state').forEach(button => {
    const selected = button.dataset.state === value.stateID;
    button.setAttribute('aria-pressed', String(selected)); button.querySelector('.check').textContent = selected ? '✓' : '';
  });
  document.querySelectorAll('#leds i').forEach((dot, index) => {
    const led = value.leds?.[index];
    dot.style.backgroundColor = led?.enabled ? led.color : '#858893';
    dot.style.opacity = led?.enabled ? Math.max(.2, led.brightness) : .25;
  });
  $('delivery').textContent = value.testing ? `Testing ${value.testColor}…` : !value.connected ? 'Saved locally · waiting for Q' : value.applied ? 'Saved · showing on Q' : 'Saved · applying to Q…';
  $('device-status').textContent = value.connected ? 'Connected' : (value.connection || 'Waiting for Q');
  $('device-id').textContent = value.deviceID || '—'; $('firmware').textContent = value.firmware || '—'; $('port').textContent = value.port || '—';
  $('test').disabled = !value.connected; $('test').textContent = value.testing ? 'Stop light test' : 'Test lights';
  if (value.gesture && value.gestureSequence !== lastGesture) {
    lastGesture = value.gestureSequence;
    $('gesture').textContent = `${gestureNames[value.gesture] || value.gesture} detected`;
    $('button-test').textContent = `${gestureNames[value.gesture] || value.gesture} detected`;
    clearTimeout(gestureTimer); gestureTimer = setTimeout(() => { $('gesture').textContent = 'Same action as pressing Q.'; }, 5000);
  }
}
$('press').onclick = () => send({ operation: 'press' });
$('brightness').oninput = () => { $('brightness-value').value = `${$('brightness').value}%`; };
$('brightness').onchange = () => send({ operation: 'setBrightness', brightness: Number($('brightness').value) / 100 });
$('settings-toggle').onclick = () => {
  settings = !settings; $('home').hidden = settings; $('settings').hidden = !settings;
  $('page-title').textContent = settings ? 'Settings' : 'Availability';
  $('settings-toggle').querySelector('span').textContent = settings ? 'Done' : 'Settings';
};
$('test').onclick = () => send({ operation: snapshot.testing ? 'cancelTest' : 'test' });
$('quit').onclick = () => window.q.quit();
window.q.subscribe(render);
window.q.snapshot().then(render).catch(error => problem(error.message));
