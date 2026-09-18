const { EventEmitter } = require('node:events');
const { spawn } = require('node:child_process');

function validateCommand(command) {
  if (!command || typeof command !== 'object') throw new Error('Invalid command');
  switch (command.operation) {
    case 'snapshot': case 'press': case 'test': case 'cancelTest':
      return { operation: command.operation };
    case 'setState':
      if (!['available', 'focus', 'busy', 'away', 'offline'].includes(command.stateID)) throw new Error('Invalid availability');
      return { operation: 'setState', stateID: command.stateID };
    case 'setBrightness':
      if (!Number.isFinite(command.brightness) || command.brightness < 0.1 || command.brightness > 1) throw new Error('Invalid brightness');
      return { operation: 'setBrightness', brightness: command.brightness };
    default: throw new Error('Unsupported command');
  }
}

class EngineBridge extends EventEmitter {
  constructor(executable, settings, { port } = {}) {
    super();
    this.executable = executable; this.settings = settings; this.port = port;
    this.latest = null; this.stopping = false; this.pending = '';
  }
  start() {
    const args = ['serve', '--settings', this.settings];
    if (this.port) args.push('--port', this.port);
    this.child = spawn(this.executable, args, { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', chunk => {
      this.pending += chunk;
      if (this.pending.length > 65536) { this.emit('problem', 'Q engine sent an oversized message'); this.child.kill(); return; }
      let end;
      while ((end = this.pending.indexOf('\n')) >= 0) {
        const line = this.pending.slice(0, end); this.pending = this.pending.slice(end + 1);
        try {
          const value = JSON.parse(line);
          if (value.type !== 'snapshot' || value.protocolVersion !== 1) throw new Error('Incompatible Q engine');
          this.latest = value; this.emit('snapshot', value);
        } catch (error) { this.emit('problem', error.message); }
      }
    });
    this.child.stderr.on('data', chunk => this.emit('problem', chunk.toString().trim().slice(0, 2000)));
    this.child.stdin.on('error', error => { if (!this.stopping) this.emit('problem', error.message); });
    this.child.on('error', error => this.emit('problem', `Cannot start Q engine: ${error.message}`));
    this.child.on('exit', code => {
      if (!this.stopping) this.emit('problem', `Q engine stopped (${code ?? 'signal'}). Close and reopen Q. Your settings are preserved.`);
    });
  }
  send(command) {
    const value = validateCommand(command);
    if (!this.child?.stdin.writable || this.stopping) throw new Error('Q engine is unavailable');
    if (this.child.stdin.writableLength > 8192) throw new Error('Q is busy; try again shortly');
    this.child.stdin.write(JSON.stringify(value) + '\n');
  }
  async stop() {
    this.stopping = true;
    const child = this.child;
    if (!child || child.exitCode !== null || child.signalCode) return;
    await new Promise(resolve => {
      const timer = setTimeout(() => { child.kill(); resolve(); }, 7000);
      child.once('exit', () => { clearTimeout(timer); resolve(); });
      child.stdin.end();
    });
  }
}
module.exports = { EngineBridge, validateCommand };
