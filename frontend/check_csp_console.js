const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    headless: true,
    channel: 'chrome',
  });
  const page = await browser.newPage();
  const messages = [];
  page.on('console', (msg) => {
    messages.push({ type: msg.type(), text: msg.text() });
  });
  page.on('pageerror', (err) => {
    messages.push({ type: 'pageerror', text: String(err) });
  });
  const url = process.argv[2] || 'http://127.0.0.1:9090/';
  const response = await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);
  console.log('STATUS', response && response.status());
  console.log('CSP_HEADER', response && response.headers()['content-security-policy']);
  console.log('TITLE', await page.title());
  const csp = messages.filter((m) => /content security policy|refused/i.test(m.text));
  console.log('CSP_MESSAGE_COUNT', csp.length);
  for (const m of csp) {
    console.log('CSP', m.type, m.text.slice(0, 400));
  }
  console.log('TOTAL_CONSOLE', messages.length);
  for (const m of messages.slice(0, 20)) {
    console.log('CONSOLE', m.type, m.text.slice(0, 200));
  }
  await page.screenshot({ path: 'output/playwright/csp-check.png', fullPage: false });
  await browser.close();
})().catch((err) => {
  console.error('FAIL', err);
  process.exit(1);
});
