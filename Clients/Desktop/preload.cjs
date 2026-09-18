const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('q', {
  snapshot: () => ipcRenderer.invoke('q:get'),
  command: command => ipcRenderer.invoke('q:command', command),
  quit: () => ipcRenderer.invoke('q:quit'),
  subscribe: callback => {
    const handler = (_event, value) => callback(value);
    ipcRenderer.on('q:snapshot', handler);
    return () => ipcRenderer.removeListener('q:snapshot', handler);
  }
});
