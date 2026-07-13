const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

async function main() {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  
  await page.setViewportSize({ width: 1440, height: 900 });
  
  console.log("Navigating to https://lordflix.org/ ...");
  try {
    await page.goto('https://lordflix.org/', { waitUntil: 'networkidle', timeout: 30000 });
  } catch (err) {
    console.log("Network idle wait failed, trying DOMContentLoaded...", err.message);
    try {
      await page.goto('https://lordflix.org/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    } catch (e) {
      console.log("Navigation failed completely, but maybe page is partially loaded?", e.message);
    }
  }

  // Sleep another 5 seconds for client-side hydration
  await new Promise(resolve => setTimeout(resolve, 5000));

  const screenshotPath = 'C:\\Users\\Aryaroop Majumder\\.gemini\\antigravity-ide\\brain\\c710ec7a-cc03-46a3-9bbc-5b1c24cfe03a\\lordflix_home.png';
  await page.screenshot({ path: screenshotPath });
  console.log(`Screenshot saved to ${screenshotPath}`);

  // Analyze page styles and layout
  const pageDetails = await page.evaluate(() => {
    const getStyles = (el) => {
      if (!el) return null;
      const s = window.getComputedStyle(el);
      return {
        backgroundColor: s.backgroundColor,
        color: s.color,
        fontFamily: s.fontFamily,
        fontSize: s.fontSize,
        padding: s.padding,
        margin: s.margin
      };
    };

    const bodyStyles = getStyles(document.body);
    const header = document.querySelector('header') || document.querySelector('nav');
    const headerStyles = getStyles(header);

    const headerLinks = [];
    if (header) {
      header.querySelectorAll('a, button').forEach(el => {
        headerLinks.push({
          text: el.innerText.trim(),
          tagName: el.tagName,
          classes: el.className
        });
      });
    }

    const headings = Array.from(document.querySelectorAll('h1, h2, h3')).map(h => ({
      tag: h.tagName,
      text: h.innerText.trim()
    }));

    const card = document.querySelector('a[href*="/movie/"], a[href*="/series/"], div[class*="card"], div[class*="item"]');
    const cardStyles = getStyles(card);
    const cardClasses = card ? card.className : '';

    return {
      title: document.title,
      bodyStyles,
      headerStyles,
      headerLinks,
      headings,
      cardStyles,
      cardClasses,
      htmlSummary: document.body.innerHTML.substring(0, 3000)
    };
  });

  console.log("=== LORDFLIX ANALYSIS ===");
  console.log("Title:", pageDetails.title);
  console.log("Body Styles:", JSON.stringify(pageDetails.bodyStyles, null, 2));
  console.log("Header Styles:", JSON.stringify(pageDetails.headerStyles, null, 2));
  console.log("Header Links/Buttons:", JSON.stringify(pageDetails.headerLinks.slice(0, 15), null, 2));
  console.log("Headings:", JSON.stringify(pageDetails.headings, null, 2));
  console.log("Card Styles:", JSON.stringify(pageDetails.cardStyles, null, 2));
  console.log("Card Classes:", pageDetails.cardClasses);
  console.log("=========================");

  await browser.close();
}

main().catch(console.error);
