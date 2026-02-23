const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const fs = require('fs');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      enableRemoteModule: false,
      preload: path.join(__dirname, 'preload.js')
    },
    icon: path.join(__dirname, '../restodocks_flutter/assets/images/logo.png'),
    show: false,
    titleBarStyle: 'default'
  });

  // Content Security Policy для безопасности
  mainWindow.webContents.session.webRequest.onHeadersReceived((details, callback) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        'Content-Security-Policy': [
          "default-src 'self'; " +
          "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " +
          "style-src 'self' 'unsafe-inline'; " +
          "img-src 'self' data: https:; " +
          "font-src 'self' data:; " +
          "connect-src 'self' https: wss:; " +
          "object-src 'none'; " +
          "base-uri 'self'; " +
          "form-action 'self';"
        ]
      }
    });
  });

  // Проверяем и загружаем Flutter веб-приложение
  const webPath = path.join(__dirname, '../restodocks_flutter/build/web/index.html');

  if (fs.existsSync(webPath)) {
    mainWindow.loadFile(webPath);
  } else {
    // Если веб-приложение не собрано, показываем сообщение
    mainWindow.loadURL(`data:text/html,
      <html>
        <body style="font-family: Arial, sans-serif; text-align: center; padding: 50px;">
          <h1>Restodocks Desktop</h1>
          <p>Веб-приложение не найдено. Запустите:</p>
          <code style="background: #f0f0f0; padding: 10px; display: block; margin: 20px;">
            npm run build-web
          </code>
          <button onclick="location.reload()">Перезагрузить</button>
        </body>
      </html>
    `);
  }

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  // Внешние ссылки открываются в браузере по умолчанию
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  // Dev tools в development режиме
  if (process.env.NODE_ENV === 'development') {
    mainWindow.webContents.openDevTools();
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});

// IPC handlers для безопасного API
ipcMain.handle('open-external', async (event, url) => {
  try {
    await shell.openExternal(url);
  } catch (error) {
    console.error('Failed to open external URL:', error);
  }
});

ipcMain.handle('show-message', async (event, message) => {
  dialog.showMessageBox(mainWindow, {
    type: 'info',
    message: message
  });
});

ipcMain.handle('select-file', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile']
  });
  return result.filePaths[0];
});

ipcMain.handle('save-file', async (event, data) => {
  const result = await dialog.showSaveDialog(mainWindow, {
    filters: [{ name: 'All Files', extensions: ['*'] }]
  });
  if (!result.canceled && result.filePath) {
    fs.writeFileSync(result.filePath, data);
  }
});