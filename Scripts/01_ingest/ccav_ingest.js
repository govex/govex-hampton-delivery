/**
 * CCAV Hampton Childcare Provider Ingestion Script
 * ─────────────────────────────────────────────────
 * Scrapes the ChildCare Aware of Virginia search tool (stage.worklifesystems.com)
 * for all Hampton, VA childcare providers and downloads a dated CSV to your
 * Downloads folder.
 *
 * OUTPUT: CCAV_ingest_YYYY-MM-DD.csv  (in browser's download location)
 * Move to: Data/CCAV_ingest_YYYY-MM-DD.csv in the project directory.
 *
 * ── HOW TO USE ──────────────────────────────────────────────────────────────
 *
 * Step 1 — Open this URL in Chrome:
 *   https://stage.worklifesystems.com/parent/25
 *
 * Step 2 — Click "Guest Account" on the login page.
 *
 * Step 3 — Complete the reCAPTCHA (human required — the script cannot do this).
 *   After passing, you'll be taken to the Search For Programs page.
 *   The search should already be filtered to Hampton (107 results).
 *   If not, open "Search Criteria", set City = Hampton, and click Find.
 *
 * Step 4 — Open Chrome DevTools: Cmd+Option+J (Mac) or Ctrl+Shift+J (Windows)
 *   Make sure you're on the Console tab.
 *
 * Step 5 — Paste this entire script into the console and press Enter.
 *   The script will page through all results automatically and download the CSV.
 *
 * Step 6 — Move the downloaded file to the project Data/ directory.
 *   The file is named CCAV_ingest_YYYY-MM-DD.csv using today's date.
 *
 * ── NOTES ───────────────────────────────────────────────────────────────────
 * - This captures CCAV-reported hours, capacity, and age ranges as of the
 *   download date. Phone-verified overrides are applied separately in the
 *   build_provider_table.qmd pipeline.
 * - Subsidy acceptance is not shown on this search page — it is sourced from
 *   the All Centers local CSV (Hampton_Childcare_Providers_All_Centers.csv).
 * - If the site times out mid-scrape, refresh, pass CAPTCHA again, and re-run.
 * ────────────────────────────────────────────────────────────────────────────
 */

(async function ingestCCAV() {

  // ── 1. Confirm we're on the right page ──────────────────────────────────
  const resultsEl = document.querySelector('#contentResults');
  if (!resultsEl) {
    alert(
      'ERROR: Could not find #contentResults on this page.\n\n' +
      'Make sure you are on the Search For Programs results page\n' +
      '(107 results, filtered to Hampton) before running this script.'
    );
    return;
  }

  const countText = resultsEl.innerText;
  if (!countText.includes('107 results') && !countText.includes('results')) {
    const proceed = confirm(
      'Expected 107 Hampton results but the page shows something different.\n\n' +
      countText.slice(0, 200) + '\n\n' +
      'Proceed anyway?'
    );
    if (!proceed) return;
  }

  // ── 2. Parser — extract one provider record from a panel element ─────────
  function parsePanel(panel) {
    const txt = panel.innerText.replace(/\s+/g, ' ').trim();
    const links = panel.querySelectorAll('a');

    const name        = links[0]?.innerText?.trim() || '';
    const director    = links[1]?.innerText?.trim() || '';
    const address     = txt.match(/(\d+[^,]+,\s*Hampton[^,]*VA\s*\d{5})/i)?.[1]?.trim() || '';
    const phone       = txt.match(/\((\d{3})\)\s*(\d{3})-(\d{4})/)?.[0] || '';
    // type may include "Program Type Offers: Faith Based, Mixed Delivery" etc.
    const type        = txt.match(/Type:\s*(.*?)(?=\s+License Type:)/)?.[1]?.trim() || '';
    const licenseType = txt.match(/License Type:\s*(.*?)(?=\s+(?:License ID:|Capacity:|Ages Served:|Child Care Licensing))/)?.[1]?.trim() || '';
    const licenseId   = txt.match(/License ID:\s*(\S+(?:\s+\S+)?)/)?.[1]?.trim() || '';
    const capacity    = txt.match(/Capacity:\s*(\d+)/)?.[1] || '';
    // ages: "1 Month - 12 Years 11 Months"
    const ages        = txt.match(/Ages Served:\s*(.*?)(?=\s+(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Child Care Licensing))/)?.[1]?.trim() || '';
    // hours: "Monday - Friday 6:00am - 6:00pm"
    const hours       = txt.match(/((?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)[^]*?\d+:\d+(?:am|pm)\s*-\s*\d+:\d+(?:am|pm))/i)?.[1]?.replace(/\s+/g, ' ').trim() || '';
    // financialAssistance: under "Other Information", terminates at "Our Schedule"
    const financialAssistance = txt.match(/Financial Assistance:\s*(.*?)(?=\s+Our Schedule)/)?.[1]?.trim() || '';
    // specialServices: tab-separated (no colon), appears at end of panel
    const specialServices = txt.match(/Special Services\s*&\s*Therapy\s+(.+)/)?.[1]?.trim() || '';

    return { name, director, address, phone, type, licenseType, licenseId, capacity, ages, hours, financialAssistance, specialServices };
  }

  // ── 3. Parse the currently visible page of results ───────────────────────
  function parsePage() {
    const panels = document.querySelectorAll('.provider-panel.countTotal');
    return Array.from(panels).map(parsePanel);
  }

  // ── 4. Wait until a specific page number is shown in the header ──────────
  function waitForPage(pageNum, timeoutMs = 20000) {
    return new Promise((resolve, reject) => {
      const start = Date.now();
      const check = setInterval(() => {
        const header = document.querySelector('#contentResults')?.innerText || '';
        if (header.includes('Page ' + pageNum + '/')) {
          clearInterval(check);
          resolve();
        } else if (Date.now() - start > timeoutMs) {
          clearInterval(check);
          reject(new Error('Timed out waiting for page ' + pageNum));
        }
      }, 300);
    });
  }

  // ── 5. Click a pagination link by its visible label ──────────────────────
  function clickPageLink(pageNum) {
    const link = Array.from(document.querySelectorAll('a'))
      .find(a => a.innerText.trim() === String(pageNum));
    if (!link) throw new Error('Could not find pagination link for page ' + pageNum);
    link.click();
  }

  // ── 6. Scrape all pages ──────────────────────────────────────────────────
  console.log('Starting CCAV ingest — collecting page 1...');
  const allProviders = parsePage();
  console.log('  Page 1: ' + allProviders.length + ' records');

  // Determine total pages from header text
  const totalPagesMatch = document.querySelector('#contentResults')
    ?.innerText.match(/Page \d+\/(\d+)/);
  const totalPages = totalPagesMatch ? parseInt(totalPagesMatch[1]) : 5;
  console.log('  Total pages detected: ' + totalPages);

  for (let pg = 2; pg <= totalPages; pg++) {
    clickPageLink(pg);
    await waitForPage(pg);
    await new Promise(r => setTimeout(r, 500)); // small buffer after load
    const pageData = parsePage();
    allProviders.push(...pageData);
    console.log('  Page ' + pg + ': ' + pageData.length + ' records (running total: ' + allProviders.length + ')');
  }

  console.log('Scrape complete: ' + allProviders.length + ' total providers');

  // ── 7. Build CSV ─────────────────────────────────────────────────────────
  const cols = ['name', 'director', 'address', 'phone', 'type',
                'licenseType', 'licenseId', 'capacity', 'ages', 'hours',
                'financialAssistance', 'specialServices'];

  const esc = v => v ? '"' + v.replace(/"/g, '""') + '"' : '';

  const csvRows = [
    cols.join(','),
    ...allProviders.map(r => cols.map(c => esc(r[c])).join(','))
  ];
  const csv = csvRows.join('\n');

  // ── 8. Download with dated filename ─────────────────────────────────────
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
  const filename = 'CCAV_ingest_' + today + '.csv';

  const blob = new Blob([csv], { type: 'text/csv' });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href     = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);

  // ── 9. Validate count ────────────────────────────────────────────────────
  const expectedTotal = 109; // update if Hampton result count changes
  if (allProviders.length !== expectedTotal) {
    console.warn(
      '⚠️  Expected ' + expectedTotal + ' records but got ' + allProviders.length + '.\n' +
      '   Check if the last page loaded completely, or if the Hampton filter changed.'
    );
  }

  console.log('✅ Downloaded: ' + filename + ' (' + allProviders.length + ' rows)');
  console.log('   Move to: Data/' + filename + ' in the project directory.');

})();
