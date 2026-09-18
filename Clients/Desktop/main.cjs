const { app, BrowserWindow, ipcMain, Menu, Tray, nativeImage, screen } = require('electron');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { EngineBridge } = require('./bridge.cjs');

app.setName('Q Portable');
// Test/development overrides are deliberately unavailable in distributed apps.
if (!app.isPackaged && process.env.Q_DESKTOP_DATA) app.setPath('userData', process.env.Q_DESKTOP_DATA);
const locked = app.requestSingleInstanceLock();
let panel, tray, engine, quitting = false, stopped = false, problem = '';
const uiURL = pathToFileURL(path.join(__dirname, 'ui', 'index.html')).href;
const publish = () => {
  if (panel && !panel.isDestroyed()) panel.webContents.send('q:snapshot', { ...engine?.latest, problem });
};
function showPanel(atTray = false) {
  if (!panel) return;
  if (atTray && tray && process.platform === 'win32') {
    const bounds = tray.getBounds();
    const area = screen.getDisplayNearestPoint({ x: bounds.x, y: bounds.y }).workArea;
    const [width, height] = panel.getSize();
    panel.setPosition(Math.max(area.x, Math.min(bounds.x - width + bounds.width, area.x + area.width - width)),
      Math.max(area.y, Math.min(bounds.y - height, area.y + area.height - height)));
  }
  if (panel.isMinimized()) panel.restore();
  panel.show(); panel.focus();
}
if (!locked) app.quit();
else {
  app.on('second-instance', () => showPanel());
  app.whenReady().then(() => {
    Menu.setApplicationMenu(null);
    const enginePath = app.isPackaged
      ? path.join(process.resourcesPath, 'engine', process.platform === 'win32' ? 'q.exe' : 'q')
      : process.env.Q_ENGINE_PATH;
    panel = new BrowserWindow({
      width: 340, height: Math.min(580, screen.getPrimaryDisplay().workArea.height - 60), minWidth: 320, minHeight: 420, useContentSize: true,
      title: 'Q', resizable: true, show: false, autoHideMenuBar: true,
      backgroundColor: '#f6f6f8', icon: path.join(__dirname, 'ui', 'QLogo.png'),
      webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true }
    });
    panel.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    panel.webContents.on('will-navigate', event => event.preventDefault());
    panel.webContents.session.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
    panel.webContents.session.webRequest.onBeforeRequest((details, callback) => callback({ cancel: !details.url.startsWith('file://') && !details.url.startsWith('devtools://') }));
    panel.on('close', event => {
      // Linux always remains reachable through a regular window/taskbar; tray
      // support varies by desktop, so closing quits there.
      if (!quitting && tray && process.platform === 'win32') { event.preventDefault(); panel.hide(); }
    });
    panel.once('ready-to-show', () => panel.show());
    panel.loadURL(uiURL);
    try {
      const icon = nativeImage.createFromPath(path.join(__dirname, 'ui', 'QLogo.png')).resize({ width: 24, height: 24 });
      tray = new Tray(icon);
      tray.setToolTip('Q — Availability');
      tray.setContextMenu(Menu.buildFromTemplate([{ label: 'Open Q', click: () => showPanel(true) }, { type: 'separator' }, { label: 'Quit Q', click: () => app.quit() }]));
      tray.on('click', () => showPanel(true));
    } catch { /* The regular window remains available if no tray exists. */ }
    const trusted = event => event.sender === panel.webContents && event.senderFrame?.url === uiURL;
    ipcMain.handle('q:get', event => { if (!trusted(event)) throw new Error('Invalid sender'); return { ...engine?.latest, problem }; });
    ipcMain.handle('q:command', (event, command) => {
      if (!trusted(event)) throw new Error('Invalid sender');
      if (!engine) throw new Error(problem || 'Q engine unavailable');
      engine.send(command);
    });
    ipcMain.handle('q:quit', event => { if (trusted(event)) app.quit(); });
    if (!enginePath) { problem = 'Q engine is missing. Use a packaged build or set Q_ENGINE_PATH for development.'; publish(); return; }
    engine = new EngineBridge(enginePath, path.join(app.getPath('userData'), 'settings.json'), {
      port: !app.isPackaged ? process.env.Q_ENGINE_PORT : undefined
    });
    engine.on('snapshot', () => { problem = ''; publish(); });
    engine.on('problem', message => {
      problem = message;
      if (engine.latest) engine.latest = { ...engine.latest, connected: false, applied: false };
      publish();
    });
    engine.start();
  });
  app.on('window-all-closed', () => app.quit());
  app.on('before-quit', event => {
    if (stopped) return;
    event.preventDefault();
    if (quitting) return;
    quitting = true;
    Promise.resolve(engine?.stop()).finally(() => { stopped = true; tray?.destroy(); app.quit(); });
  });
}
