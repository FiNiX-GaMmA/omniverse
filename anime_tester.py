#!/usr/bin/env python3
import re
import sys
import time
import urllib.parse
import concurrent.futures
import json
import requests

# ANSI colors for beautiful CLI formatting
RESET = "\033[0m"
BOLD = "\033[1m"
GREEN = "\033[92m"
CYAN = "\033[96m"
YELLOW = "\033[93m"
RED = "\033[91m"
BLUE = "\033[94m"

FMHY_STREAMING_URL = "https://raw.githubusercontent.com/wiki/fmhy/FMHY/Streaming.md"

HIANIME_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Referer": "https://hianime.to/",
    "Accept": "*/*",
}

def fetch_fmhy_anime_sites():
    """Fetches FMHY's Streaming.md and extracts anime streaming site URLs."""
    print(f"{CYAN}[FMHY] Fetching live anime streaming directory from FMHY...{RESET}")
    try:
        resp = requests.get(FMHY_STREAMING_URL, timeout=10)
        if resp.status_code != 200:
            print(f"{RED}[FMHY] Failed to fetch FMHY Streaming guide. Status: {resp.status_code}{RESET}")
            return []
        
        content = resp.text
        # Locate the "## ▷ Anime Streaming" section up to the next "## ▷" heading
        anime_section_match = re.search(r"## ▷ Anime Streaming(.*?)(## ▷|$)", content, re.DOTALL | re.IGNORECASE)
        if not anime_section_match:
            print(f"{RED}[FMHY] Could not locate Anime Streaming section in wiki.{RESET}")
            return []
        
        anime_section = anime_section_match.group(1)
        # Find all markdown links [Name](URL)
        links = re.findall(r"\[([^\]]+)\]\((https?://[^)]+)\)", anime_section)
        
        sites = []
        seen_domains = set()
        for name, url in links:
            # Clean up URLs (strip trailing paths, keep base domain)
            parsed_url = urllib.parse.urlparse(url)
            base_url = f"{parsed_url.scheme}://{parsed_url.netloc}"
            domain = parsed_url.netloc.lower()
            
            # Avoid duplicate domain checks and filter out non-streaming tools/GitHub guides
            if domain not in seen_domains and not any(x in domain for x in ["github.com", "reddit.com", "discord.gg", "greasyfork.org"]):
                seen_domains.add(domain)
                sites.append({"name": name, "url": base_url})
                
        print(f"{GREEN}[FMHY] Extracted {len(sites)} unique anime streaming domains from FMHY guide!{RESET}")
        return sites
    except Exception as e:
        print(f"{RED}[FMHY] Error parsing FMHY: {e}{RESET}")
        return []

def test_site_latency(site):
    """Pings a domain to determine its latency and basic accessibility."""
    url = site["url"]
    start_time = time.time()
    try:
        # Use a quick 4-second timeout to filter out slow/dead sites
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"}
        resp = requests.head(url, headers=headers, timeout=4, allow_redirects=True)
        if resp.status_code >= 400:
            # Fallback to GET if HEAD is blocked/forbidden
            resp = requests.get(url, headers=headers, timeout=4, allow_redirects=True)
        
        latency = (time.time() - start_time) * 1000
        is_up = resp.status_code < 400
        return {
            "name": site["name"],
            "url": url,
            "up": is_up,
            "status": resp.status_code,
            "latency_ms": round(latency, 1) if is_up else float('inf')
        }
    except Exception:
        return {
            "name": site["name"],
            "url": url,
            "up": False,
            "status": 0,
            "latency_ms": float('inf')
        }

def check_one_piece_1088_on_hianime(base_url):
    """Tests if a specific HiAnime base domain contains One Piece episode 1088."""
    print(f"{CYAN}[Check] Querying {base_url} for One Piece Episode 1088...{RESET}")
    slug = "one-piece-100"
    watch_url = f"{base_url}/watch/{slug}"
    
    try:
        # Step 1: Fetch the main watch page
        headers = HIANIME_HEADERS.copy()
        headers["Referer"] = base_url + "/"
        watch_resp = requests.get(watch_url, headers=headers, timeout=8)
        if watch_resp.status_code != 200 or not watch_resp.text:
            return False, "Failed to load watch page (HTTP " + str(watch_resp.status_code) + ")"
        
        # Step 2: Extract the anime ID (data-id) from the page
        anime_id_match = re.search(r'id=["\']ani_detail["\'][^>]*data-id=["\']([^"\']+)["\']', watch_resp.text, re.IGNORECASE)
        if not anime_id_match:
            # Try fallback patterns
            anime_id_match = re.search(r'data-id=["\']([^"\']+)["\']', watch_resp.text, re.IGNORECASE)
            
        if not anime_id_match:
            return False, "Could not extract anime ID from watch page HTML"
            
        anime_id = anime_id_match.group(1)
        
        # Step 3: Fetch the episode list via AJAX
        ajax_url = f"{base_url}/ajax/v2/episode/list/{anime_id}"
        ajax_headers = headers.copy()
        ajax_headers["X-Requested-With"] = "XMLHttpRequest"
        ajax_resp = requests.get(ajax_url, headers=ajax_headers, timeout=8)
        if ajax_resp.status_code != 200 or not ajax_resp.text:
            return False, f"Failed to fetch episode list AJAX (HTTP {ajax_resp.status_code})"
        
        # Parse AJAX json/html
        try:
            data = ajax_resp.json()
            html_content = data.get("html", "")
        except Exception:
            html_content = ajax_resp.text
            
        # Step 4: Check if episode 1088 exists in the episode list HTML
        # Look for data-number="1088" or title="Episode 1088"
        has_1088 = "data-number=\"1088\"" in html_content or "data-number='1088'" in html_content or "Episode 1088" in html_content
        
        if has_1088:
            # Extract episodeId for validation
            ep_id_match = re.search(r'data-id=["\']([^"\']+)["\'][^>]*data-number=["\']1088["\']', html_content) or \
                          re.search(r'data-number=["\']1088["\'][^>]*data-id=["\']([^"\']+)["\']', html_content)
            ep_id = ep_id_match.group(1) if ep_id_match else "Unknown"
            return True, f"Found! (Episode ID: {ep_id})"
        else:
            return False, "Episode 1088 not found in the available range."
            
    except Exception as e:
        return False, f"Error: {str(e)}"

def main():
    print(f"{BOLD}{MAGENTA}===================================================={RESET}")
    print(f"{BOLD}{MAGENTA}      OMNIVERSE ANIME PIPELINE & CDN TESTER         {RESET}")
    print(f"{BOLD}{MAGENTA}===================================================={RESET}\n")
    
    # 1. Fetch live sites
    sites = fetch_fmhy_anime_sites()
    if not sites:
        print(f"{YELLOW}[Warn] Using local fallback FMHY anime streaming domains...{RESET}")
        sites = [
            {"name": "Miruro (Main)", "url": "https://www.miruro.com"},
            {"name": "Miruro (TV)", "url": "https://miruro.tv"},
            {"name": "All Manga (Main)", "url": "https://allmanga.to"},
            {"name": "animepahe (Main)", "url": "https://animepahe.pw"},
            {"name": "KickAssAnime", "url": "https://kaa.lt"},
            {"name": "Animetsu", "url": "https://animetsu.net"},
            {"name": "AnimeX", "url": "https://animex.one"},
            {"name": "Anidap", "url": "https://anidap.se"},
            {"name": "Yenime", "url": "https://yenime.net"},
            {"name": "HiAnime (to)", "url": "https://hianime.to"},
            {"name": "HiAnime (tv)", "url": "https://hianime.tv"},
            {"name": "HiAnime (bz)", "url": "https://hianime.bz"}
        ]
        
    # 2. Test latency and availability concurrently
    print(f"\n{CYAN}[Pinger] Testing latencies of all {len(sites)} sites concurrently...{RESET}")
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=15) as executor:
        future_to_site = {executor.submit(test_site_latency, s): s for s in sites}
        for future in concurrent.futures.as_completed(future_to_site):
            results.append(future.result())
            
    # Sort results by latency (lowest first, dead sites last)
    results.sort(key=lambda x: x["latency_ms"])
    
    # Print beautiful latency report
    print(f"\n{BOLD}{YELLOW}------------------------------------------------------------{RESET}")
    print(f"{BOLD}{YELLOW}               ANIME SITE ACCESSIBILITY REPORT              {RESET}")
    print(f"{BOLD}{YELLOW}------------------------------------------------------------{RESET}")
    print(f"{BOLD}{'SITE NAME':<24} | {'LATENCY':<10} | {'STATUS':<8} | {'URL':<30}{RESET}")
    print(f"------------------------------------------------------------")
    
    alive_hianime_domains = []
    
    for r in results:
        status_color = GREEN if r["up"] else RED
        latency_str = f"{r['latency_ms']} ms" if r["up"] else "OFFLINE"
        latency_color = GREEN if r["up"] and r["latency_ms"] < 300 else (YELLOW if r["up"] else RED)
        
        print(f"{r['name']:<24} | {latency_color}{latency_str:<10}{RESET} | {status_color}HTTP {r['status']:<4}{RESET} | {BLUE}{r['url']}{RESET}")
        
        # Track active HiAnime domains for One Piece check
        if r["up"] and "hianime" in r["url"]:
            alive_hianime_domains.append(r["url"])
            
    print(f"------------------------------------------------------------\n")
    
    # 3. Perform One Piece Episode 1088 validation check
    print(f"{BOLD}{CYAN}[Edge-Case Check] Testing if any streaming site hosts One Piece Episode 1088 (Edge Case)...{RESET}")
    
    passed = False
    passed_domain = None
    
    if not alive_hianime_domains:
        # Check standard defaults even if ping failed (sometimes HEAD requests block but GET works on watch endpoints)
        alive_hianime_domains = ["https://hianime.to", "https://hianime.nz", "https://hianime.bz"]
        
    for domain in alive_hianime_domains[:4]:  # Check top 4 fastest alive HiAnime domains
        is_ok, msg = check_one_piece_1088_on_hianime(domain)
        if is_ok:
            print(f"  {GREEN}➔ {domain}: PASS! {msg}{RESET}")
            passed = True
            passed_domain = domain
        else:
            print(f"  {RED}➔ {domain}: FAIL! {msg}{RESET}")
            
    print(f"\n{BOLD}{YELLOW}===================================================={RESET}")
    if passed:
        print(f"{BOLD}{GREEN}        STATUS: SUCCESS / ALL CHECKS PASS!          {RESET}")
        print(f"{GREEN}One Piece Ep 1088 resolved perfectly via {passed_domain}!{RESET}")
    else:
        print(f"{BOLD}{RED}           STATUS: WARNING / CHECKS FAILED          {RESET}")
        print(f"{RED}No responsive source had One Piece Ep 1088 listed.{RESET}")
    print(f"{BOLD}{YELLOW}===================================================={RESET}\n")

if __name__ == "__main__":
    main()
