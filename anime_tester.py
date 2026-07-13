#!/usr/bin/env python3
import time
import concurrent.futures
import requests

# ANSI colors
RESET = "\033[0m"
BOLD = "\033[1m"
GREEN = "\033[92m"
CYAN = "\033[96m"
YELLOW = "\033[93m"
RED = "\033[91m"
BLUE = "\033[94m"

ANI_CLI_ENDPOINTS = [
    {"name": "AllManga", "url": "https://allmanga.to"},
    {"name": "AllAnime API", "url": "https://api.allanime.day/api"},
    {"name": "AniList GraphQL", "url": "https://graphql.anilist.co"},
]

UA = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
}


def test_endpoint(site):
    url = site["url"]
    start = time.time()
    try:
        # HEAD first; fallback to GET for hosts that reject HEAD.
        resp = requests.head(url, headers=UA, timeout=5, allow_redirects=True)
        if resp.status_code >= 400:
            resp = requests.get(url, headers=UA, timeout=5, allow_redirects=True)
        latency_ms = (time.time() - start) * 1000
        return {
            "name": site["name"],
            "url": url,
            "up": resp.status_code < 400,
            "status": resp.status_code,
            "latency_ms": round(latency_ms, 1),
        }
    except Exception:
        return {
            "name": site["name"],
            "url": url,
            "up": False,
            "status": 0,
            "latency_ms": float("inf"),
        }


def main():
    print(f"{BOLD}{CYAN}=============================================={RESET}")
    print(f"{BOLD}{CYAN}       OMNIVERSE ANI-CLI ENDPOINT TEST       {RESET}")
    print(f"{BOLD}{CYAN}=============================================={RESET}\n")

    print(f"{CYAN}[Probe] Testing ani-cli endpoints...{RESET}")
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = [executor.submit(test_endpoint, s) for s in ANI_CLI_ENDPOINTS]
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())

    results.sort(key=lambda r: r["latency_ms"])

    print(f"\n{BOLD}{YELLOW}----------------------------------------------{RESET}")
    print(f"{BOLD}{YELLOW}{'ENDPOINT':<16} | {'LATENCY':<10} | {'STATUS':<8}{RESET}")
    print(f"{BOLD}{YELLOW}----------------------------------------------{RESET}")

    fastest = None
    for r in results:
        status_color = GREEN if r["up"] else RED
        latency_str = f"{r['latency_ms']} ms" if r["up"] else "OFFLINE"
        latency_color = GREEN if r["up"] and r["latency_ms"] < 300 else (YELLOW if r["up"] else RED)
        print(
            f"{r['name']:<16} | {latency_color}{latency_str:<10}{RESET} | "
            f"{status_color}HTTP {r['status']:<4}{RESET} | {BLUE}{r['url']}{RESET}"
        )
        if r["up"] and fastest is None:
            fastest = r

    print(f"{BOLD}{YELLOW}----------------------------------------------{RESET}\n")

    if fastest:
        print(
            f"{GREEN}Fastest reachable ani-cli endpoint: "
            f"{fastest['name']} ({fastest['latency_ms']} ms){RESET}"
        )
    else:
        print(f"{RED}No ani-cli endpoints are reachable right now.{RESET}")


if __name__ == "__main__":
    main()
