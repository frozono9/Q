const path = require('node:path');
const fs = require('node:fs/promises');
const { execFileSync } = require('node:child_process');

(async () => {
  const { packager } = await import('@electron/packager');
  const root = path.resolve(__dirname, '../..');
  const platform = process.platform;
  if (!['win32', 'linux'].includes(platform)) throw new Error('Desktop packaging is Windows/Linux only');
  const engine = path.join(root, '.build/packages', platform === 'win32' ? 'q-windows-x64' : 'q-linux-x86_64');
  await fs.access(engine);
  const paths = await packager({
    dir: __dirname, out: path.join(__dirname, 'out'), name: 'QPortable',
    executableName: platform === 'win32' ? 'QPortable' : 'q-portable',
    platform, arch: 'x64', electronVersion: require('./package.json').devDependencies.electron,
    asar: true, overwrite: true, prune: true,
    ignore: [/^\/tests($|\/)/, /^\/test-results($|\/)/, /^\/out($|\/)/, /^\/package\.cjs$/]
  });
  const destination = paths[0];
  await fs.cp(engine, path.join(destination, 'resources/engine'), { recursive: true });
  await fs.copyFile(path.join(root, 'Docs/PORTABLE_DESKTOP.md'), path.join(destination, 'README.md'));
  const commit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' });
  await fs.writeFile(path.join(destination, 'COMMIT.txt'), commit);
  const archive = path.join(root, '.build/packages', platform === 'win32' ? 'q-desktop-windows-x64.zip' : 'q-desktop-linux-x86_64.tar.gz');
  if (platform === 'win32') {
    // Paths travel as environment values, never interpolated PowerShell source.
    execFileSync('powershell.exe', ['-NoProfile', '-Command', 'Compress-Archive -LiteralPath $env:Q_PACK_SOURCE -DestinationPath $env:Q_PACK_ARCHIVE -Force'], {
      env: { ...process.env, Q_PACK_SOURCE: destination, Q_PACK_ARCHIVE: archive }, stdio: 'inherit'
    });
  } else execFileSync('tar', ['-czf', archive, '-C', path.dirname(destination), path.basename(destination)], { stdio: 'inherit' });
  console.log(archive);
})().catch(error => { console.error(error); process.exitCode = 1; });
