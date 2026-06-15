import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const APP_PATHS = [
  '/index.html',
  '/holiday-request/index.html',
  '/credit-hours/index.html',
  '/kiln-log/index.html',
  '/shift-tracker/index.html',
  '/user-management/index.html'
];

function mimeTypeFor(filePath){
  if (filePath.endsWith('.html')) return 'text/html; charset=utf-8';
  if (filePath.endsWith('.js')) return 'text/javascript; charset=utf-8';
  if (filePath.endsWith('.css')) return 'text/css; charset=utf-8';
  if (filePath.endsWith('.svg')) return 'image/svg+xml';
  if (filePath.endsWith('.json')) return 'application/json; charset=utf-8';
  if (filePath.endsWith('.webmanifest')) return 'application/manifest+json; charset=utf-8';
  return 'application/octet-stream';
}

function createStaticServer(){
  return http.createServer((req, res) => {
    const reqPath = decodeURIComponent((req.url || '/').split('?')[0] || '/');
    const relativePath = reqPath === '/' ? '/index.html' : reqPath;
    const absPath = path.join(root, relativePath);
    if (!absPath.startsWith(root)) {
      res.statusCode = 403;
      res.end('Forbidden');
      return;
    }
    if (!fs.existsSync(absPath) || fs.statSync(absPath).isDirectory()) {
      res.statusCode = 404;
      res.end('Not Found');
      return;
    }
    res.setHeader('Content-Type', mimeTypeFor(absPath));
    fs.createReadStream(absPath).pipe(res);
  });
}

async function loadPlaywright(){
  try {
    return await import('playwright');
  } catch (err) {
    const installerPath = path.join(root, 'node_modules', 'playwright', 'index.mjs');
    if (fs.existsSync(installerPath)) return import(pathToFileURL(installerPath).href);
    throw new Error(
      'Playwright is not installed. Run: npm i -D playwright && npx playwright install chromium webkit'
    );
  }
}

async function runSuite(browserName, browserType, baseUrl){
  const browser = await browserType.launch({ headless: true });
  const errors = [];
  try {
    for (const appPath of APP_PATHS) {
      const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
      const pageErrors = [];
      page.on('console', (msg) => {
        if (msg.type() === 'error') pageErrors.push(msg.text());
      });
      page.on('pageerror', (error) => pageErrors.push(error && error.message ? error.message : String(error)));
      const response = await page.goto(baseUrl + appPath, { waitUntil: 'domcontentloaded', timeout: 30000 });
      if (!response || !response.ok()) {
        errors.push(`[${browserName}] ${appPath}: failed to load (${response ? response.status() : 'no response'})`);
      }
      await page.waitForTimeout(400);
      if (pageErrors.length) {
        errors.push(`[${browserName}] ${appPath}: ${pageErrors[0]}`);
      }
      await page.close();
    }
  } finally {
    await browser.close();
  }
  return errors;
}

async function main(){
  const playwright = await loadPlaywright();
  const server = createStaticServer();
  await new Promise((resolve) => server.listen(4173, '127.0.0.1', resolve));
  const baseUrl = 'http://127.0.0.1:4173';
  const allErrors = [];
  try {
    allErrors.push(...await runSuite('chromium', playwright.chromium, baseUrl));
    allErrors.push(...await runSuite('webkit', playwright.webkit, baseUrl));
  } finally {
    server.close();
  }
  if (allErrors.length) {
    allErrors.forEach((line) => console.error(line));
    process.exit(1);
  }
  console.log('Browser regression checks passed (chromium + webkit).');
}

main().catch((error) => {
  console.error(error && error.message ? error.message : String(error));
  process.exit(1);
});
