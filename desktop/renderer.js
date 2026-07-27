// ==============================================================================
// Omniverse Desktop — Core Renderer Controller
// ==============================================================================

// Domains observed to be DNS-sinkholed by some ISPs (e.g. Airtel RPZ). The
// mobile apps use the vidsrc-embed.* / *.su domains, which stay reachable.
const BLOCKED_VIDSRC_DOMAINS = ["vidsrc.me", "vidsrc.to", "vidsrc.xyz"];
const DEFAULT_EMBED_PROVIDER = "vsembed.ru";
const DEFAULT_VIDSRC_DOMAIN = DEFAULT_EMBED_PROVIDER;
function resolveSavedVidsrcDomain() {
  const saved = localStorage.getItem("omni_vidsrc_domain");
  const legacyVidsrcDefaults = [
    "vidcore.created.app",
    ...BLOCKED_VIDSRC_DOMAINS,
    "vsembed.ru",
    "vsembed.su",
    "vidsrcme.ru",
    "vidsrc-embed.ru",
    "vidsrc-embed.su",
    "vidsrcme.su",
    "vsrc.su",
    "vidsrc.net",
    "vidcore.org",
    "www.vidcore.org",
  ];
  if (!saved || legacyVidsrcDefaults.includes(saved)) {
    localStorage.setItem("omni_vidsrc_domain", DEFAULT_EMBED_PROVIDER);
    return DEFAULT_EMBED_PROVIDER;
  }
  return saved;
}

// Global Application State
let detailModalRequestToken = 0;

let state = {
  tmdbToken: localStorage.getItem("omni_tmdb_token") || "",
  vidsrcDomain: resolveSavedVidsrcDomain(),
  currentScreen: "home",
  activeStudio: "",
  selectedMedia: null,
  activeWebview: null,
  adBlockCount: 0,
  iptvCountries: [],
  iptvChannels: [],
  filteredIptvChannels: [],

  // Trakt Sync credentials
  traktToken: localStorage.getItem("omni_trakt_token") || "",
  traktRefreshToken: localStorage.getItem("omni_trakt_refresh_token") || "",
  traktTokenExpiresAt:
    parseInt(localStorage.getItem("omni_trakt_expires_at") || "0") || 0,
  traktUsername: localStorage.getItem("omni_trakt_username") || "",
  traktClientId: localStorage.getItem("omni_trakt_client_id") || "",
  traktClientSecret: localStorage.getItem("omni_trakt_client_secret") || "",
  pixeldrainApiKey: localStorage.getItem("omni_pixeldrain_key") || "",

  // TVDB & AniList credentials
  tvdbApiKey: localStorage.getItem("omni_tvdb_key") || "",
  tvdbPin: localStorage.getItem("omni_tvdb_pin") || "",
  anilistAccessToken: localStorage.getItem("omni_anilist_token") || "",

  watchHistory: JSON.parse(localStorage.getItem("omni_watch_history") || "[]"),
  returnToDetailContext: null,
  activeDirectPlayback: null,
};

const STUDIO_PROVIDER_MAP = {
  netflix: { provider: "8", label: "Netflix" },
  prime: { provider: "9", label: "Amazon Prime Video" },
  disney: { provider: "337", label: "Disney Plus" },
  appletvplus: { provider: "350", label: "Apple TV Plus" },
  appletv: { provider: "2", label: "Apple TV" },
  hulu: { provider: "15", label: "Hulu" },
  hbo: { provider: "1899", label: "HBO Max" },
  paramount: { provider: "531", label: "Paramount Plus" },
  peacock: { provider: "386", label: "Peacock Premium" },
  crunchyroll: { provider: "283", label: "Crunchyroll" },
  starz: { provider: "43", label: "Starz" },
  amcplus: { provider: "526", label: "AMC Plus" },

  // Legacy aliases
  apple: { provider: "350", label: "Apple TV Plus" },
  marvel: { company: "420", label: "Marvel" },
  pixar: { company: "3", label: "Pixar" },
  a24: { company: "41077", label: "A24" },
  warner: { company: "174", label: "Warner Bros" },
  universal: { company: "33", label: "Universal" },
  sony: { company: "5", label: "Sony" },
};

const TMDB_PROVIDER_LOGO_OVERRIDES = {
  526: "https://image.tmdb.org/t/p/w154/ovmu6uot1XVvsemM2dDySXLiX57.jpg",
  8: "https://image.tmdb.org/t/p/w154/pbpMk2JmcoNnQwx5JGpXngfoWtp.jpg",
  9: "https://image.tmdb.org/t/p/w154/pvske1MyAoymrs5bguRfVqYiM9a.jpg",
  337: "https://image.tmdb.org/t/p/w154/97yvRBw1GzX7fXprcF80er19ot.jpg",
  350: "https://image.tmdb.org/t/p/w154/SPnB1qiCkYfirS2it3hZORwGVn.jpg",
  15: "https://image.tmdb.org/t/p/w154/bxBlRPEPpMVDc4jMhSrTf2339DW.jpg",
  1899: "https://image.tmdb.org/t/p/w154/jbe4gVSfRlbPTdESXhEKpornsfu.jpg",
  531: "https://image.tmdb.org/t/p/w154/fts6X10Jn4QT0X6ac3udKEn2tJA.jpg",
  386: "https://image.tmdb.org/t/p/w154/2aGrp1xw3qhwCYvNGAJZPdjfeeX.jpg",
  283: "https://image.tmdb.org/t/p/w154/fzN5Jok5Ig1eJ7gyNGoMhnLSCfh.jpg",
};

const ANILIST_GRAPHQL = "https://graphql.anilist.co";

const screenScrollPositions = {
  home: 0,
  movies: 0,
  tv: 0,
  anime: 0,
  livetv: 0,
  settings: 0,
  search: 0,
};

const infiniteState = {
  movies: {
    page: 1,
    totalPages: 1,
    loading: false,
    hasMore: true,
    seen: new Set(),
  },
  tv: {
    page: 1,
    totalPages: 1,
    loading: false,
    hasMore: true,
    seen: new Set(),
  },
  anime: {
    page: 1,
    loading: false,
    hasMore: true,
    seen: new Set(),
  },
  provider: {
    active: false,
    key: "",
    cfg: null,
    activeType: "movie",
    movie: {
      page: 0,
      totalPages: 1,
      loading: false,
      hasMore: true,
      seen: new Set(),
    },
    tv: {
      page: 0,
      totalPages: 1,
      loading: false,
      hasMore: true,
      seen: new Set(),
    },
  },
};

// Initialize UI on startup
document.addEventListener("DOMContentLoaded", async () => {
  setupPlatformWindowDecorations();
  loadSavedPreferences();
  await hydrateProviderRailLogos();
  switchScreen("home");
  renderCatalogFeeds();
  setupSearchInput();
  setupLiveTvCenter();
  setupInfiniteScrollLoading();
  renderContinueWatching(); // Initial local history render
  setupAdblockObserver();
  setupWebviewFailObserver();
  lucide.createIcons();

  // Dynamically resolve and display installed version in settings
  try {
    if (
      window.electron &&
      typeof window.electron.getAppVersion === "function"
    ) {
      const actualVer = await window.electron.getAppVersion();
      if (actualVer) {
        APP_VERSION = actualVer;
        const verLabel = document.getElementById("update-version-label");
        if (verLabel) verLabel.textContent = `Version ${actualVer} (Installed)`;
      }
    }
  } catch (_) {}

  // Background cloud sync continue-watching if Trakt connected
  if (state.traktToken) {
    pullFromTrakt();
  }

  // Silently check for newer releases in the background and notify
  setTimeout(() => {
    checkAppUpdates(true);
  }, 3000);
});

window.addEventListener("beforeunload", () => {
  stopActiveDirectPlayback({ saveFinal: true });
});

// Configure Window Controls based on OS
async function setupPlatformWindowDecorations() {
  try {
    let platform = "win32"; // default fallback for Windows/Linux
    if (window.electron && typeof window.electron.getPlatform === "function") {
      platform = await window.electron.getPlatform();
    } else {
      // Fallback detection using navigator.platform
      const isMac = /Mac|iPad|iPhone|iPod/.test(navigator.platform);
      platform = isMac ? "darwin" : "win32";
    }

    if (platform !== "darwin") {
      // Windows and Linux have custom draggable title bar buttons
      const controls = document.getElementById("window-controls");
      if (controls) controls.classList.remove("hidden");
    }
  } catch (err) {
    console.warn(
      "[Omniverse] Failed to detect platform window decorations:",
      err,
    );
    // Show them anyway as a safe fallback unless we are on Mac
    const isMac = /Mac|iPad|iPhone|iPod/.test(navigator.platform);
    if (!isMac) {
      const controls = document.getElementById("window-controls");
      if (controls) controls.classList.remove("hidden");
    }
  }
}

// Load configurations
function loadSavedPreferences() {
  document.getElementById("tmdb-token-input").value = state.tmdbToken;
  document.getElementById("vidsrc-domain-select").value = state.vidsrcDomain;

  if (document.getElementById("trakt-token-input"))
    document.getElementById("trakt-token-input").value = state.traktToken;
  if (document.getElementById("trakt-client-id-input"))
    document.getElementById("trakt-client-id-input").value =
      state.traktClientId;
  if (document.getElementById("trakt-client-secret-input"))
    document.getElementById("trakt-client-secret-input").value =
      state.traktClientSecret;
  if (document.getElementById("pixeldrain-key-input"))
    document.getElementById("pixeldrain-key-input").value =
      state.pixeldrainApiKey;
  if (document.getElementById("tvdb-key-input"))
    document.getElementById("tvdb-key-input").value = state.tvdbApiKey;
  if (document.getElementById("tvdb-pin-input"))
    document.getElementById("tvdb-pin-input").value = state.tvdbPin;
  if (document.getElementById("anilist-token-input"))
    document.getElementById("anilist-token-input").value =
      state.anilistAccessToken;
}

async function hydrateProviderRailLogos() {
  const logoNodes = Array.from(
    document.querySelectorAll("img.studio-logo[data-provider-id]"),
  );
  if (!logoNodes.length) return;

  let providersById = new Map();
  if (state.tmdbToken && state.tmdbToken.trim()) {
    const providersResponse = await fetchTmdb("watch/providers/movie", {
      watch_region: "US",
    });
    const providers = (providersResponse && providersResponse.results) || [];
    providersById = new Map(
      providers.map((provider) => [String(provider.provider_id), provider]),
    );
  }

  logoNodes.forEach((img) => {
    const providerId = String(img.dataset.providerId || "");
    const provider = providersById.get(providerId);
    const overrideSrc = TMDB_PROVIDER_LOGO_OVERRIDES[providerId] || "";
    const tmdbSrc =
      provider && provider.logo_path
        ? `https://image.tmdb.org/t/p/w154${provider.logo_path}`
        : "";
    const src = overrideSrc || tmdbSrc || img.getAttribute("src") || "";

    const tile = img.closest("button");
    const fallbackLabel = tile
      ? tile.querySelector("[data-provider-fallback]")
      : null;

    if (!src) {
      img.removeAttribute("src");
      img.classList.add("hidden");
      if (fallbackLabel) fallbackLabel.classList.remove("hidden");
      return;
    }

    img.src = src;
    if (provider && provider.provider_name) {
      img.alt = `${provider.provider_name} logo`;
      if (tile) tile.title = provider.provider_name;
    }
    img.classList.remove("hidden");
    if (fallbackLabel) fallbackLabel.classList.add("hidden");
  });
}

// Cross-platform fetch helper (Electron IPC -> fallback to native fetch)
async function appFetch(url, method = "GET", headers = {}, body = null) {
  if (window.electron && window.electron.iptvFetch) {
    return await window.electron.iptvFetch(url, method, headers, body);
  } else {
    try {
      const options = { method, headers };
      if (body)
        options.body = typeof body === "string" ? body : JSON.stringify(body);
      const response = await fetch(url, options);
      const html = await response.text();
      return { ok: response.ok, status: response.status, html };
    } catch (err) {
      return { ok: false, status: 0, error: err.message, html: "" };
    }
  }
}

// TMDB API Client Helpers
async function fetchTmdb(path, params = {}) {
  const token = state.tmdbToken.trim();
  if (!token) return null;

  const urlParams = new URLSearchParams({
    language: "en-US",
    include_adult: "false",
    ...params,
  });
  // Force a fresh pull on app start/refresh instead of relying on cached API
  // responses. TMDB ignores unknown params, but the cache key stays unique.
  urlParams.set("_ts", String(Date.now()));

  if (!token.startsWith("ey")) {
    urlParams.set("api_key", token);
  }

  const url = `https://api.themoviedb.org/3/${path}?${urlParams.toString()}`;
  const headers = {
    Accept: "application/json",
    "Cache-Control": "no-cache",
    Pragma: "no-cache",
  };
  if (token.startsWith("ey")) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  try {
    const res = await appFetch(url, "GET", headers);
    if (!res.ok) throw new Error(res.error || `HTTP ${res.status}`);
    return JSON.parse(res.html);
  } catch (e) {
    console.warn(`[TMDB API Error] Path: ${path}`, e);
    return null;
  }
}

const TMDB_GENRES = {
  28: "Action",
  12: "Adventure",
  16: "Animation",
  35: "Comedy",
  80: "Crime",
  99: "Documentary",
  18: "Drama",
  10751: "Family",
  14: "Fantasy",
  36: "History",
  27: "Horror",
  10402: "Music",
  9648: "Mystery",
  10749: "Romance",
  878: "Science Fiction",
  10770: "TV Movie",
  53: "Thriller",
  10752: "War",
  37: "Western",
  10759: "Action",
  10762: "Kids",
  10763: "News",
  10764: "Reality",
  10765: "Sci-Fi & Fantasy",
  10766: "Soap",
  10767: "Talk",
  10768: "War",
};

function mediaPlaceholder(title) {
  return (
    "https://ui-avatars.com/api/?background=111&color=fff&size=500&name=" +
    encodeURIComponent(title || "Media")
  );
}

function mapTmdbItem(item, type) {
  const title = item.title || item.name || "Untitled";
  const placeholder = mediaPlaceholder(title);
  const posterPath = item.poster_path
    ? `https://image.tmdb.org/t/p/w500${item.poster_path}`
    : item.backdrop_path
      ? `https://image.tmdb.org/t/p/w780${item.backdrop_path}`
      : placeholder;
  const backdropPath = item.backdrop_path
    ? `https://image.tmdb.org/t/p/original${item.backdrop_path}`
    : item.poster_path
      ? `https://image.tmdb.org/t/p/original${item.poster_path}`
      : placeholder;
  const releaseDate = item.release_date || item.first_air_date || "";
  const year = releaseDate ? new Date(releaseDate).getFullYear() : "—";
  const genreIds = item.genre_ids || [];
  const genres = genreIds.map((id) => TMDB_GENRES[id]).filter(Boolean);
  return {
    id: `tmdb:${type}:${item.id}`,
    title: title,
    type: type,
    year: year,
    rating: item.vote_average ? item.vote_average.toFixed(1) : "—",
    tmdbId: item.id,
    poster: posterPath,
    backdrop: backdropPath,
    overview: item.overview || "No description available.",
    genres: genres,
    originalLanguage: item.original_language || "",
  };
}

// Heuristic: a TMDB title that is Japanese + Animation is almost certainly
// anime, so it should play via the AllAnime path rather than a vidsrc embed.
function isLikelyAnime(media) {
  return false;
}

function showGridLoading(containerId, label = "Pulling latest titles…") {
  const container = document.getElementById(containerId);
  if (!container) return;
  container.innerHTML = `
    <div class="col-span-full flex flex-col items-center justify-center py-10 gap-3 text-gray-500 min-h-[180px]">
      <div class="w-6 h-6 rounded-full border-2 border-brandCyan border-t-transparent animate-spin"></div>
      <span class="text-[10px] font-bold uppercase tracking-[0.24em] text-brandCyan">${label}</span>
    </div>
  `;
}

function showGridMessage(containerId, title, body, icon = "satellite") {
  const container = document.getElementById(containerId);
  if (!container) return;
  container.innerHTML = `
    <div class="col-span-full w-full min-h-[190px] rounded-2xl border border-white/[0.06] bg-white/[0.025] flex flex-col items-center justify-center text-center gap-3 p-8">
      <div class="w-12 h-12 rounded-2xl bg-brandCyan/10 border border-brandCyan/20 flex items-center justify-center text-brandCyan">
        <i data-lucide="${icon}" class="w-5 h-5"></i>
      </div>
      <div class="space-y-1 max-w-md">
        <h3 class="text-sm font-black text-white tracking-wide">${title}</h3>
        <p class="text-xs text-gray-500 leading-relaxed">${body}</p>
      </div>
    </div>
  `;
  if (window.lucide) lucide.createIcons();
}

function setHeroMessage(title, overview) {
  if (heroTimer) clearInterval(heroTimer);
  heroTimer = null;
  heroSlides = [];
  const heroBanner = document.getElementById("hero-banner");
  const heroTitle = document.getElementById("hero-title");
  const heroOverview = document.getElementById("hero-overview");
  const heroDots = document.getElementById("hero-dots");
  const heroPlayBtn = document.getElementById("hero-play-btn");
  const heroDetailBtn = document.getElementById("hero-detail-btn");
  if (heroBanner) heroBanner.style.backgroundImage = "";
  if (heroTitle) heroTitle.textContent = title;
  if (heroOverview) heroOverview.textContent = overview;
  if (heroDots) heroDots.innerHTML = "";
  if (heroPlayBtn) heroPlayBtn.onclick = () => switchScreen("settings");
  if (heroDetailBtn) heroDetailBtn.onclick = () => switchScreen("settings");
}

function mapTmdbResults(data, type) {
  return ((data && data.results) || [])
    .filter((item) => item && (item.poster_path || item.backdrop_path))
    .map((item) => mapTmdbItem(item, type));
}

function uniqueByMediaId(items, seenSet) {
  const out = [];
  (items || []).forEach((item) => {
    if (!item || !item.id || seenSet.has(item.id)) return;
    seenSet.add(item.id);
    out.push(item);
  });
  return out;
}

function createMediaPosterCard(item, isRail = false) {
  const card = document.createElement("div");
  card.onclick = () => openDetailModal(item);
  card.className =
    "media-poster-card cursor-pointer group" +
    (isRail ? " w-[180px] shrink-0" : "");
  card.innerHTML = `
    <div class="relative aspect-[2/3] w-full">
      <img src="${item.poster}" alt="${item.title}" class="w-full h-full object-cover" loading="lazy" onerror="this.onerror=null; this.src='https://ui-avatars.com/api/?background=111&color=fff&name=Media'">
      <div class="media-overlay-glass">
        <h4 class="text-white font-bold text-sm leading-tight drop-shadow-md mb-1 line-clamp-2">${item.title}</h4>
        <div class="flex items-center justify-between text-gray-300 text-[10px] font-semibold tracking-wide">
          <span>${item.year || "—"}</span>
          <span class="flex items-center gap-1"><i data-lucide="star" class="w-3 h-3 fill-amber-400 text-amber-400"></i> ${item.rating || "—"}</span>
        </div>
      </div>
    </div>
  `;
  return card;
}

function appendMediaCards(container, items, startIndex = 0, isRail = false) {
  if (!container) return;
  (items || []).forEach((item, idx) => {
    const card = createMediaPosterCard(item, isRail);
    applyCardStaggerAnimation(card, startIndex + idx);
    container.appendChild(card);
  });
  if (window.lucide) lucide.createIcons();
}

function setupInfiniteScrollLoading() {
  const viewport = document.getElementById("content-viewport");
  if (!viewport || viewport.dataset.infiniteBound === "1") return;

  let ticking = false;
  viewport.addEventListener("scroll", () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(async () => {
      ticking = false;
      const nearBottom =
        viewport.scrollTop + viewport.clientHeight >=
        viewport.scrollHeight - 520;
      if (!nearBottom) return;

      if (state.currentScreen === "movies") {
        const providerBrowser = document.getElementById("provider-browser");
        const providerActive =
          providerBrowser && !providerBrowser.classList.contains("hidden");
        if (providerActive) {
          await loadProviderSection(
            infiniteState.provider.activeType || "movie",
            true,
          );
        } else {
          await loadMoreTmdbGrid("movie");
        }
      } else if (state.currentScreen === "tv") {
        await loadMoreTmdbGrid("tv");
      } else if (state.currentScreen === "anime") {
        await loadMoreAnimeGrid();
      }
    });
  });

  viewport.dataset.infiniteBound = "1";
}

function resetTmdbInfinite(type, items) {
  const key = type === "tv" ? "tv" : "movies";
  const st = infiniteState[key];
  st.page = 1;
  st.totalPages = 500;
  st.loading = false;
  st.hasMore = true;
  st.seen = new Set((items || []).map((i) => i && i.id).filter(Boolean));
}

async function loadMoreTmdbGrid(type = "movie") {
  if (!state.tmdbToken) return;
  const key = type === "tv" ? "tv" : "movies";
  const containerId = type === "tv" ? "grid-all-tv" : "grid-all-movies";
  const st = infiniteState[key];
  if (!st || st.loading || !st.hasMore) return;

  st.loading = true;
  try {
    const nextPage = st.page + 1;
    const data = await fetchTmdbDiscover(type, nextPage);
    st.totalPages = data && data.total_pages ? data.total_pages : st.totalPages;
    const fresh = uniqueByMediaId(mapTmdbResults(data, type), st.seen);

    if (!fresh.length) {
      st.hasMore = nextPage < st.totalPages;
      st.page = nextPage;
      return;
    }

    const container = document.getElementById(containerId);
    const startIndex = container ? container.children.length : 0;
    appendMediaCards(container, fresh, startIndex, false);
    st.page = nextPage;
    st.hasMore = st.page < st.totalPages;
  } finally {
    st.loading = false;
  }
}

async function fetchDesktopRecommendationsFor(media) {
  if (!media) return [];
  if (media.tmdbId) {
    const tmdbType = media.type === "movie" ? "movie" : "tv";
    const recData = await fetchTmdb(
      `${tmdbType}/${media.tmdbId}/recommendations`,
    );
    return mapTmdbResults(recData, tmdbType);
  }
  return [];
}

function resetAnimeInfinite(items) {
  infiniteState.anime.page = 1;
  infiniteState.anime.loading = false;
  infiniteState.anime.hasMore = true;
  infiniteState.anime.seen = new Set(
    (items || []).map((i) => i && i.id).filter(Boolean),
  );
}

async function loadMoreAnimeGrid() {
  const st = infiniteState.anime;
  if (st.loading || !st.hasMore) return;

  st.loading = true;
  try {
    const nextPage = st.page + 1;
    const page = await fetchAniListDiscoverPage(nextPage);
    const raw = (page && page.media) || [];
    const mapped = raw.map(mapAniListItem).filter(Boolean);
    const fresh = uniqueByMediaId(mapped, st.seen);

    if (!fresh.length) {
      st.page = nextPage;
      st.hasMore = Boolean(page && page.pageInfo && page.pageInfo.hasNextPage);
      return;
    }

    state.animeCatalog = [...(state.animeCatalog || []), ...fresh];
    const grid = document.getElementById("grid-all-anime");
    const startIndex = grid ? grid.children.length : 0;
    appendMediaCards(grid, fresh, startIndex, false);

    st.page = nextPage;
    st.hasMore = Boolean(page && page.pageInfo && page.pageInfo.hasNextPage);
  } finally {
    st.loading = false;
  }
}

async function fetchTmdbDiscover(type, page = 1, extraParams = {}) {
  const endpoint = type === "tv" ? "discover/tv" : "discover/movie";
  const params = {
    sort_by: "popularity.desc",
    "vote_count.gte": type === "tv" ? "25" : "40",
    page: String(page),
    ...extraParams,
  };
  return await fetchTmdb(endpoint, params);
}

// Lordflix-style rotating hero carousel state
let heroSlides = [];
let heroIndex = 0;
let heroTimer = null;

function initHeroCarousel(items) {
  heroSlides = (items || [])
    .filter((m) => m && (m.backdrop || m.poster))
    .slice(0, 7);
  if (!heroSlides.length) return;
  heroIndex = 0;
  showHeroSlide(0);
  if (heroTimer) clearInterval(heroTimer);
  heroTimer = setInterval(() => {
    showHeroSlide((heroIndex + 1) % heroSlides.length);
  }, 8000);
}

function showHeroSlide(i) {
  if (!heroSlides.length) return;
  heroIndex = i;
  updateHeroBanner(heroSlides[i]);
  renderHeroDots();
}

function renderHeroDots() {
  const dots = document.getElementById("hero-dots");
  if (!dots) return;
  dots.innerHTML = "";
  heroSlides.forEach((_, i) => {
    const dot = document.createElement("button");
    dot.className =
      "h-1.5 rounded-full transition-all duration-300 " +
      (i === heroIndex
        ? "w-6 bg-white"
        : "w-1.5 bg-white/40 hover:bg-white/70");
    dot.onclick = () => {
      showHeroSlide(i);
      if (heroTimer) clearInterval(heroTimer);
    };
    dots.appendChild(dot);
  });
}

function updateHeroBanner(media) {
  const heroBanner = document.getElementById("hero-banner");
  const heroTitle = document.getElementById("hero-title");
  const heroOverview = document.getElementById("hero-overview");
  const heroPlayBtn = document.getElementById("hero-play-btn");
  const heroAddBtn = document.getElementById("hero-add-btn");
  const heroDetailBtn = document.getElementById("hero-detail-btn");

  if (!heroBanner || !media) return;

  heroBanner.style.opacity = "0.3";
  setTimeout(() => {
    heroBanner.style.backgroundImage = `url('${media.backdrop || media.poster}')`;
    if (heroTitle) heroTitle.textContent = media.title;
    if (heroOverview) heroOverview.textContent = media.overview;
    heroBanner.style.opacity = "1";

    // Replay the staggered entrance animation on the hero content block
    const heroContent = document.getElementById("hero-content");
    if (heroContent) {
      heroContent.classList.remove("hero-content-anim");
      void heroContent.offsetWidth; // force reflow to restart the animation
      heroContent.classList.add("hero-content-anim");
    }
  }, 150);

  if (heroPlayBtn) {
    heroPlayBtn.onclick = () => {
      if (media.type === "movie") {
        playStream(media);
      } else {
        openDetailModal(media);
      }
    };
  }

  if (heroAddBtn) {
    heroAddBtn.onclick = () => {
      if (window.electron && window.electron.showNotification) {
        window.electron.showNotification("My List", `${media.title} added`);
      }
    };
  }

  if (heroDetailBtn) {
    heroDetailBtn.onclick = () => openDetailModal(media);
  }
}

// Render dynamic elements from live sources only. No bundled catalogue is used.
async function renderCatalogFeeds(skipAnimeLoad = false) {
  let trendingMovies = [];
  let trendingTv = [];
  let popularMovies = [];
  let tvGridItems = [];

  if (!skipAnimeLoad) {
    showGridLoading("grid-all-anime", "Syncing AniList…");
    loadAnimeCatalog();
  }

  if (state.tmdbToken) {
    showGridLoading("grid-all-movies", "Syncing TMDB movies…");
    showGridLoading("grid-all-tv", "Syncing TMDB shows…");
    setHeroMessage(
      "Syncing latest releases…",
      "Pulling fresh trending movies, TV shows, and anime from live sources.",
    );

    const [
      trendingMoviesData,
      trendingTvData,
      popularMoviesData,
      topRatedTvData,
      onAirTvData,
    ] = await Promise.all([
      fetchTmdb("trending/movie/week"),
      fetchTmdb("trending/tv/week"),
      fetchTmdb("movie/now_playing"),
      fetchTmdb("tv/top_rated"),
      fetchTmdb("tv/on_the_air"),
    ]);

    trendingMovies = mapTmdbResults(trendingMoviesData, "movie");
    trendingTv = mapTmdbResults(trendingTvData, "tv");
    popularMovies = mapTmdbResults(popularMoviesData, "movie");
    tvGridItems = [
      ...mapTmdbResults(onAirTvData, "tv"),
      ...mapTmdbResults(topRatedTvData, "tv"),
    ];

    const movieInitial = (
      popularMovies.length ? popularMovies : trendingMovies
    ).slice(0, 24);
    const tvInitial = (tvGridItems.length ? tvGridItems : trendingTv).slice(
      0,
      24,
    );

    renderGrid("grid-all-movies", movieInitial, true);
    renderGrid("grid-all-tv", tvInitial, true);

    resetTmdbInfinite("movie", movieInitial);
    resetTmdbInfinite("tv", tvInitial);
  } else {
    showGridMessage(
      "grid-all-movies",
      "Connect TMDB to load live movies",
      "Omniverse no longer ships a bundled movie catalogue. Add your TMDB key in Settings to pull the latest trending and now-playing movies on startup.",
      "key-round",
    );
    showGridMessage(
      "grid-all-tv",
      "Connect TMDB to load live TV",
      "Add your TMDB key in Settings and this rail will populate from fresh trending, on-air, and top-rated TV data.",
      "key-round",
    );
    infiniteState.movies.hasMore = false;
    infiniteState.tv.hasMore = false;
  }

  const dynamicAnimeList = state.animeCatalog || [];
  const heroFeed = [
    ...trendingMovies,
    ...trendingTv,
    ...dynamicAnimeList,
  ].filter((m) => m && (m.backdrop || m.poster));
  if (heroFeed.length) {
    initHeroCarousel(heroFeed);
  } else if (!state.tmdbToken) {
    setHeroMessage(
      "Live catalogue only",
      "Anime will sync from AniList automatically. Add TMDB in Settings to unlock fresh movie and TV discovery.",
    );
  } else {
    setHeroMessage(
      "No live catalogue returned",
      "TMDB did not return usable image-backed results. Check your token or network and refresh again.",
    );
  }

  const categories = [];
  const blendTop10 = [];
  let mi = 0,
    si = 0,
    ai = 0;
  const maxLimit = 10;

  while (
    blendTop10.length < maxLimit &&
    (mi < trendingMovies.length ||
      si < trendingTv.length ||
      ai < dynamicAnimeList.length)
  ) {
    if (mi < trendingMovies.length) {
      blendTop10.push(trendingMovies[mi++]);
      if (blendTop10.length >= maxLimit) break;
    }
    if (si < trendingTv.length) {
      blendTop10.push(trendingTv[si++]);
      if (blendTop10.length >= maxLimit) break;
    }
    if (ai < dynamicAnimeList.length) {
      blendTop10.push(dynamicAnimeList[ai++]);
      if (blendTop10.length >= maxLimit) break;
    }
  }

  if (blendTop10.length > 0) {
    categories.push({
      id: "top_10_trending",
      title: "Top 10 Trending",
      description: "The most watched movies, TV shows, and anime this week",
      items: blendTop10,
      isTop10: true,
    });
  }

  if (trendingMovies.length > 0) {
    categories.push({
      id: "top_10_movies",
      title: "Top 10 Trending Movies",
      description: "Fresh theatrical and digital momentum from TMDB",
      items: trendingMovies.slice(0, 10),
      isTop10: true,
    });
  }

  if (trendingTv.length > 0) {
    categories.push({
      id: "top_10_tv",
      title: "Top 10 Trending TV Shows",
      description: "Series gaining the most momentum this week",
      items: trendingTv.slice(0, 10),
      isTop10: true,
    });
  }

  if (dynamicAnimeList.length > 0) {
    categories.push({
      id: "top_10_anime",
      title: "Top 10 Trending Anime",
      description: "Fresh AniList discovery picks",
      items: dynamicAnimeList.slice(0, 10),
      isTop10: true,
    });
  }

  const allItems = [...trendingMovies, ...trendingTv, ...dynamicAnimeList];
  const genresToRender = [
    "Action",
    "Comedy",
    "Drama",
    "Science Fiction",
    "Animation",
    "Horror",
    "Mystery",
  ];
  genresToRender.forEach((genre) => {
    const seen = new Set();
    const picks = [];
    for (const item of allItems) {
      const itemGenres = item.genres || [];
      if (item.type === "anime" && !itemGenres.includes("Animation")) {
        itemGenres.push("Animation");
      }
      const matchesGenre = itemGenres.some(
        (g) =>
          g.toLowerCase().includes(genre.toLowerCase()) ||
          (genre === "Science Fiction" && g.toLowerCase().includes("sci")),
      );
      if (matchesGenre && !seen.has(item.id)) {
        seen.add(item.id);
        picks.push(item);
      }
    }
    if (picks.length >= 4) {
      categories.push({
        id: `genre_${genre.toLowerCase().replace(/\s+/g, "_")}`,
        title: `Trending ${genre}`,
        description: `Live ${genre} titles refreshed from remote sources`,
        items: picks.slice(0, 15),
        isTop10: false,
      });
    }
  });

  const homeCatalogs = document.getElementById("home-catalogs");
  if (homeCatalogs) {
    homeCatalogs.innerHTML = "";
    if (!categories.length) {
      homeCatalogs.innerHTML = `
        <div class="rounded-3xl border border-white/[0.06] bg-white/[0.025] p-10 flex flex-col items-center justify-center text-center gap-3 min-h-[240px]">
          <div class="w-14 h-14 rounded-2xl bg-brandCyan/10 border border-brandCyan/20 flex items-center justify-center text-brandCyan">
            <i data-lucide="radar" class="w-6 h-6"></i>
          </div>
          <h2 class="text-xl font-black text-white">Waiting for live catalogue data</h2>
          <p class="text-sm text-gray-500 max-w-xl leading-relaxed">No bundled catalogue is used. Add a TMDB key for movies and shows; AniList anime will appear as soon as the live request completes.</p>
        </div>`;
    } else {
      categories.forEach((cat) => {
        const catSection = document.createElement("div");
        catSection.className = "space-y-3";

        const header = document.createElement("div");
        header.className = "flex items-end justify-between";
        header.innerHTML = `
          <h2 class="text-xl font-semibold text-white/90 tracking-wide drop-shadow-md">${cat.title}</h2>
          <button class="view-all-link flex items-center gap-1 text-sm font-medium text-white/50 hover:text-white transition">
            View All <i data-lucide="chevron-right" class="w-4 h-4"></i>
          </button>
        `;
        const viewAllBtn = header.querySelector(".view-all-link");
        if (viewAllBtn) {
          viewAllBtn.onclick = () => {
            if (cat.id.includes("anime")) switchScreen("anime");
            else if (cat.id.includes("tv")) switchScreen("tv");
            else switchScreen("movies");
          };
        }

        const rail = document.createElement("div");
        rail.className =
          "horizontal-rail flex overflow-x-auto gap-4 pb-4 scrollbar-none no-drag";

        cat.items.forEach((item, index) => {
          if (cat.isTop10) {
            const card = document.createElement("div");
            card.className =
              "relative flex items-end h-[220px] min-w-[210px] select-none shrink-0";
            card.onclick = () => openDetailModal(item);
            const rank = index + 1;
            card.innerHTML = `
              <span class="absolute bottom-[-10px] left-0 text-[130px] font-black leading-none text-white/[0.08] select-none pointer-events-none font-sans z-0">
                ${rank}
              </span>
              <div class="media-poster-card ml-auto w-[140px] h-[210px] cursor-pointer text-left bg-transparent relative z-10">
                <div class="relative aspect-[2/3] w-full">
                  <img src="${item.poster}" alt="${item.title}" class="w-full h-full object-cover" loading="lazy" onerror="this.onerror=null; this.src='https://ui-avatars.com/api/?background=111&color=fff&name=Media'">
                  <div class="media-overlay-glass">
                    <h4 class="text-white font-bold text-xs leading-tight drop-shadow-md mb-1 line-clamp-1">${item.title}</h4>
                    <div class="flex items-center justify-between text-gray-300 text-[10px] font-semibold tracking-wide">
                      <span>${item.year || "—"}</span>
                      <span class="flex items-center gap-1"><i data-lucide="star" class="w-3 h-3 fill-amber-400 text-amber-400"></i> ${item.rating || "—"}</span>
                    </div>
                  </div>
                </div>
              </div>
            `;
            applyCardStaggerAnimation(card, index);
            rail.appendChild(card);
          } else {
            const card = document.createElement("div");
            card.onclick = () => openDetailModal(item);
            card.className =
              "media-poster-card cursor-pointer group w-[180px] shrink-0";
            card.innerHTML = `
              <div class="relative aspect-[2/3] w-full">
                <img src="${item.poster}" alt="${item.title}" class="w-full h-full object-cover" loading="lazy" onerror="this.onerror=null; this.src='https://ui-avatars.com/api/?background=111&color=fff&name=Media'">
                <div class="media-overlay-glass">
                  <h4 class="text-white font-bold text-sm leading-tight drop-shadow-md mb-1 line-clamp-2">${item.title}</h4>
                  <div class="flex items-center justify-between text-gray-300 text-[10px] font-semibold tracking-wide">
                    <span>${item.year || "—"}</span>
                    <span class="flex items-center gap-1"><i data-lucide="star" class="w-3 h-3 fill-amber-400 text-amber-400"></i> ${item.rating || "—"}</span>
                  </div>
                </div>
              </div>
            `;
            applyCardStaggerAnimation(card, index);
            rail.appendChild(card);
          }
        });

        catSection.appendChild(header);
        catSection.appendChild(rail);
        homeCatalogs.appendChild(catSection);
      });
    }
  }

  if (skipAnimeLoad || dynamicAnimeList.length) {
    renderGrid("grid-all-anime", dynamicAnimeList, true);
    resetAnimeInfinite(dynamicAnimeList);
  }
  if (window.lucide) lucide.createIcons();
}

async function loadAnimeCatalog() {
  state.animeCatalog = [];
}

let cardRevealObserver = null;

function shouldReduceMotion() {
  return (
    typeof window !== "undefined" &&
    window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  );
}

function ensureCardRevealObserver() {
  if (cardRevealObserver || typeof IntersectionObserver === "undefined") {
    return cardRevealObserver;
  }

  cardRevealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const target = entry.target;
        target.classList.remove("stagger-card-pending");
        target.classList.add("stagger-card-enter");
        cardRevealObserver.unobserve(target);
      });
    },
    {
      root: null,
      threshold: 0.18,
      rootMargin: "0px 0px -6% 0px",
    },
  );

  return cardRevealObserver;
}

function applyCardStaggerAnimation(card, index) {
  card.style.setProperty("--stagger-index", String(index % 8));

  if (shouldReduceMotion()) {
    card.classList.remove("stagger-card-pending");
    card.classList.add("stagger-card-enter");
    return;
  }

  card.classList.add("stagger-card-pending");
  const observer = ensureCardRevealObserver();

  if (!observer) {
    card.classList.remove("stagger-card-pending");
    card.classList.add("stagger-card-enter");
    return;
  }

  observer.observe(card);
}

function renderGrid(containerId, items, isLordflix = true) {
  const container = document.getElementById(containerId);
  if (!container) return;
  const safeItems = (items || []).filter(Boolean);
  container.innerHTML = "";

  if (!safeItems.length) {
    showGridMessage(
      containerId,
      "No live results yet",
      "This section only displays remote catalogue data. Try refreshing or check the related API connection.",
      "radar",
    );
    return;
  }

  if (isLordflix) {
    appendMediaCards(container, safeItems, 0, false);
    return;
  }

  safeItems.forEach((item, index) => {
    const card = document.createElement("div");
    card.onclick = () => openDetailModal(item);
    card.className =
      "media-card bg-transparent rounded-lg p-0 cursor-pointer text-left";
    card.innerHTML = `
      <div class="group relative aspect-[2/3] rounded-lg overflow-hidden bg-brandTert mb-2 shadow-lg">
        <img src="${item.poster}" alt="${item.title}" class="w-full h-full object-cover transition duration-300 group-hover:scale-105 group-hover:opacity-50" loading="lazy" onerror="this.onerror=null; this.src='https://ui-avatars.com/api/?background=111&color=fff&name=Media'">
        <div class="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition duration-300">
          <i data-lucide="play-circle" class="w-10 h-10 text-white drop-shadow-lg"></i>
        </div>
        <span class="absolute top-1.5 right-1.5 bg-black/80 text-white font-bold text-[9px] px-1.5 py-0.5 rounded flex items-center gap-0.5">
          ★ ${item.rating}
        </span>
      </div>
      <div class="px-1 space-y-0.5">
        <h4 class="text-xs font-semibold text-gray-200 truncate leading-snug">${item.title}</h4>
        <div class="flex items-center justify-between text-[10px] text-gray-500 font-medium">
          <span>${item.year}</span>
          <span class="uppercase text-[9px] tracking-wider text-brandCyan">${item.type}</span>
        </div>
      </div>
    `;
    applyCardStaggerAnimation(card, index);
    container.appendChild(card);
  });
}

function setMoviesProviderMode(enabled) {
  const providerBrowser = document.getElementById("provider-browser");
  const defaultHeader = document.getElementById("movies-default-header");

  if (providerBrowser)
    providerBrowser.classList.toggle("hidden", !Boolean(enabled));
  if (defaultHeader) defaultHeader.classList.toggle("hidden", Boolean(enabled));
}

function setProviderTabUi(type) {
  const moviesBtn = document.getElementById("provider-tab-movies");
  const tvBtn = document.getElementById("provider-tab-tv");
  const heading = document.getElementById("provider-active-heading");
  const isMovie = type !== "tv";

  if (moviesBtn) {
    moviesBtn.className =
      "rounded-full px-6 py-2 text-sm font-bold transition-all " +
      (isMovie ? "bg-white text-black" : "text-white/70 hover:text-white");
  }
  if (tvBtn) {
    tvBtn.className =
      "rounded-full px-6 py-2 text-sm font-bold transition-all " +
      (!isMovie ? "bg-white text-black" : "text-white/70 hover:text-white");
  }
  if (heading) heading.textContent = isMovie ? "Movies" : "Series";
}

function renderProviderHero(cfg) {
  const logoEl = document.getElementById("provider-hero-logo");
  const nameEl = document.getElementById("provider-hero-name");

  if (nameEl) nameEl.textContent = cfg.label || "Provider";
  if (logoEl) {
    const logoFromOverrides = cfg.provider
      ? TMDB_PROVIDER_LOGO_OVERRIDES[String(cfg.provider)]
      : "";
    logoEl.src = logoFromOverrides || logoEl.src || "";
  }
}

async function loadProviderSection(type = "movie", append = false) {
  const studioKey = (state.activeStudio || "").toLowerCase();
  const cfg = STUDIO_PROVIDER_MAP[studioKey];
  const container = document.getElementById("grid-all-movies");
  if (!container || !cfg) return;

  const providerState = infiniteState.provider[type === "tv" ? "tv" : "movie"];
  if (
    !providerState ||
    providerState.loading ||
    (append && !providerState.hasMore)
  ) {
    return;
  }

  const nextPage = append ? providerState.page + 1 : 1;
  providerState.loading = true;

  try {
    if (!append) {
      providerState.page = 0;
      providerState.totalPages = 1;
      providerState.hasMore = true;
      providerState.seen = new Set();
      showGridLoading("grid-all-movies", "Loading provider titles…");
    }

    const params = { sort_by: "popularity.desc" };
    if (cfg.provider) {
      params.with_watch_providers = cfg.provider;
      params.watch_region = "US";
    } else {
      params.with_companies = cfg.company;
    }

    if (type === "tv") params["vote_count.gte"] = "25";
    else params["vote_count.gte"] = "40";

    const data = await fetchTmdbDiscover(type, nextPage, params);
    providerState.totalPages =
      data && data.total_pages ? data.total_pages : providerState.totalPages;

    const mapped = mapTmdbResults(data, type).filter((i) => i.poster);
    const items = uniqueByMediaId(mapped, providerState.seen);

    if (!items.length) {
      providerState.page = nextPage;
      providerState.hasMore = providerState.page < providerState.totalPages;
      if (!append) {
        showGridMessage(
          "grid-all-movies",
          "No titles available",
          "No titles are available right now for this provider section.",
          "radar",
        );
      }
      return;
    }

    if (!append) {
      renderGrid("grid-all-movies", items, true);
    } else {
      const startIndex = container.children.length;
      appendMediaCards(container, items, startIndex, false);
    }

    providerState.page = nextPage;
    providerState.hasMore = providerState.page < providerState.totalPages;
  } finally {
    providerState.loading = false;
  }
}

async function switchProviderSection(type = "movie") {
  if (!state.activeStudio) return;
  infiniteState.provider.activeType = type === "tv" ? "tv" : "movie";
  setProviderTabUi(type);
  await loadProviderSection(infiniteState.provider.activeType, false);
}

// Single Page Screen Routing
function switchScreen(screenName) {
  state.currentScreen = screenName;
  if (screenName !== "movies") {
    state.activeStudio = "";
    infiniteState.provider.active = false;
  }

  // Hide all screens
  const screens = [
    "home",
    "movies",
    "tv",
    "anime",
    "livetv",
    "settings",
    "search",
  ];
  screens.forEach((s) => {
    const el = document.getElementById(`screen-${s}`);
    if (el) el.classList.add("hidden");
    const btn = document.getElementById(`nav-${s}`);
    if (btn) btn.classList.remove("nav-active");
  });

  // Show active screen
  const activeEl = document.getElementById(`screen-${screenName}`);
  if (activeEl) activeEl.classList.remove("hidden");

  const activeBtn = document.getElementById(`nav-${screenName}`);
  if (activeBtn) activeBtn.classList.add("nav-active");

  if (screenName === "movies") {
    setMoviesProviderMode(false);
  }

  // Pause Live TV player if leaving Live TV screen
  if (screenName !== "livetv") {
    const player = document.getElementById("livetv-player");
    if (player) player.pause();
  }


}

// Studio Filtering logic
async function filterByStudio(studio) {
  switchScreen("movies");
  state.activeStudio = (studio || "").toLowerCase();

  const cfg = STUDIO_PROVIDER_MAP[state.activeStudio];
  if (!state.tmdbToken) {
    setMoviesProviderMode(false);
    showGridMessage(
      "grid-all-movies",
      "Connect TMDB for live network filtering",
      "Studio and platform rails are now pulled only from TMDB. Add your key in Settings to load this live catalogue.",
      "key-round",
    );
    return;
  }

  if (!cfg) {
    setMoviesProviderMode(false);
    showGridMessage(
      "grid-all-movies",
      "No live provider mapping",
      `No TMDB provider/company mapping is configured for ${studio.toUpperCase()}.`,
      "radar",
    );
    return;
  }

  infiniteState.provider.active = true;
  infiniteState.provider.key = state.activeStudio;
  infiniteState.provider.cfg = cfg;
  setMoviesProviderMode(true);
  renderProviderHero(cfg);
  await switchProviderSection("movie");

  if (window.electron && window.electron.showNotification) {
    window.electron.showNotification(
      "Provider Loaded",
      `Browsing ${cfg.label} movies and series`,
    );
  }
}

function parsePositiveIntOrNull(value) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function normalizeWatchType(type) {
  const lower = (type || "").toString().toLowerCase();
  if (lower === "series") return "tv";
  if (lower === "live_tv") return "livetv";
  return lower;
}

function removeWatchProgressByItemId(itemId, options = {}) {
  const { syncRemote = true } = options;
  const key = (itemId || "").toString().trim();
  if (!key) return false;

  const next = (state.watchHistory || []).filter((h) => h && h.itemId !== key);
  if (next.length === (state.watchHistory || []).length) return false;

  state.watchHistory = next;
  localStorage.setItem("omni_watch_history", JSON.stringify(state.watchHistory));
  renderContinueWatching();

  if (syncRemote && state.traktToken) {
    pushToTrakt();
  }
  return true;
}

function recordWatchProgress(
  media,
  positionMs,
  durationMs,
  episodeContext = {},
  options = {},
) {
  const { syncRemote = false } = options;
  if (!media || !media.id) return false;

  const type = normalizeWatchType(media.type);
  if (!type || type === "livetv") return false;

  const duration = Math.round(Number(durationMs) || 0);
  if (duration <= 0) return false;

  const position = Math.max(0, Math.round(Number(positionMs) || 0));
  const fraction = position / duration;
  if (position < 5000 || fraction >= 0.95) {
    if (fraction >= 0.95) {
      removeWatchProgressByItemId(media.id, { syncRemote });
    }
    return false;
  }

  const seasonNumber = parsePositiveIntOrNull(episodeContext.seasonNumber);
  const episodeNumber = parsePositiveIntOrNull(episodeContext.episodeNumber);
  const fallbackEpisodeTitle = episodeNumber ? `Episode ${episodeNumber}` : null;

  const entry = {
    id: null,
    itemId: media.id,
    title: media.title || "Unknown",
    showTitle: media.title || "Unknown",
    type,
    posterPath: media.posterPath || media.poster || null,
    backdropPath: media.backdropPath || media.backdrop || null,
    seasonNumber,
    episodeNumber,
    episodeTitle: episodeContext.episodeTitle || fallbackEpisodeTitle,
    positionMs: position,
    durationMs: duration,
    lastWatchedAt: Date.now(),
  };

  saveWatchProgress(entry, { syncRemote });
  return true;
}

function findResumePositionMs(media, seasonNumber = null, episodeNumber = null) {
  if (!media || !media.id) return null;
  const raw = (state.watchHistory || []).find((h) => h && h.itemId === media.id);
  if (!raw) return null;

  const entry = normalizeWatchProgress(raw);
  const wantedSeason = parsePositiveIntOrNull(seasonNumber);
  const wantedEpisode = parsePositiveIntOrNull(episodeNumber);
  const savedSeason = parsePositiveIntOrNull(entry.seasonNumber || entry.season);
  const savedEpisode = parsePositiveIntOrNull(entry.episodeNumber || entry.episode);

  if (wantedEpisode && savedEpisode && wantedEpisode !== savedEpisode) return null;
  if (wantedSeason && savedSeason && wantedSeason !== savedSeason) return null;

  const savedPos = parsePositiveIntOrNull(entry.positionMs);
  const savedDuration = parsePositiveIntOrNull(entry.durationMs);
  if (!savedPos || !savedDuration || savedPos < 5000) return null;
  if (savedPos / savedDuration >= 0.95) return null;

  return savedPos;
}

function stopActiveDirectPlayback(options = {}) {
  const { saveFinal = true, completed = false } = options;
  const active = state.activeDirectPlayback;
  if (!active) return;

  if (active.intervalId) {
    clearInterval(active.intervalId);
  }
  state.activeDirectPlayback = null;

  if (saveFinal && typeof active.persist === "function") {
    active.persist({ syncRemote: true, completed });
  }
}

function startDirectPlaybackTracking(video, media, seasonNumber = null, episodeNumber = null) {
  if (!video || !media || !media.id) return;

  const trackedType = normalizeWatchType(media.type);
  if (!trackedType || trackedType === "livetv") return;

  const context = {
    seasonNumber: parsePositiveIntOrNull(seasonNumber),
    episodeNumber: parsePositiveIntOrNull(episodeNumber),
    episodeTitle: parsePositiveIntOrNull(episodeNumber)
      ? `Episode ${parsePositiveIntOrNull(episodeNumber)}`
      : null,
  };

  const tracker = {
    media,
    video,
    context,
    intervalId: null,
    persist({ syncRemote = false, completed = false } = {}) {
      const durationSec = Number(video.duration);
      if (!Number.isFinite(durationSec) || durationSec <= 0) return;

      const duration = Math.round(durationSec * 1000);
      const position = completed
        ? duration
        : Math.max(0, Math.round((Number(video.currentTime) || 0) * 1000));

      recordWatchProgress(media, position, duration, context, { syncRemote });
    },
  };

  tracker.intervalId = setInterval(() => {
    tracker.persist({ syncRemote: false, completed: false });
  }, 10_000);

  state.activeDirectPlayback = tracker;
}

function captureReturnToDetailContext(media, season = null, episode = null) {
  if (!media) return;
  state.returnToDetailContext = {
    media: { ...(media || {}) },
    season: parsePositiveIntOrNull(season),
    episode: parsePositiveIntOrNull(episode),
  };
}

function focusEpisodeCardInDetail(season, episode) {
  const grid = document.getElementById("episodes-grid");
  if (!grid) return;

  const target = grid.querySelector(
    `[data-season="${String(season)}"][data-episode="${String(episode)}"]`,
  );
  if (!target) return;

  grid
    .querySelectorAll(".episode-focused")
    .forEach((node) => node.classList.remove("episode-focused"));

  target.scrollIntoView({
    behavior: "smooth",
    inline: "center",
    block: "nearest",
  });

  if (typeof target.focus === "function") {
    target.focus({ preventScroll: true });
  }

  target.classList.add("episode-focused");
  setTimeout(() => target.classList.remove("episode-focused"), 1200);
}

async function restoreDetailFromPlaybackContext() {
  const ctx = state.returnToDetailContext;
  if (!ctx || !ctx.media) return false;

  try {
    await openDetailModal(ctx.media);

    if (!ctx.episode) return true;

    const seasonSelector = document.getElementById("season-selector");
    if (!seasonSelector) return true;

    const desiredSeason = ctx.season || 1;
    const hasDesiredSeason = Array.from(seasonSelector.options || []).some(
      (opt) => opt.value === String(desiredSeason),
    );

    if (hasDesiredSeason) {
      seasonSelector.value = String(desiredSeason);
    }

    await loadSeasonEpisodes();
    const activeSeason = parsePositiveIntOrNull(seasonSelector.value) || 1;
    focusEpisodeCardInDetail(activeSeason, ctx.episode);
    return true;
  } catch (err) {
    console.warn("[Omniverse] Failed to restore detail modal context:", err);
    return false;
  }
}

function scrollRecommendationsRail(direction = 1) {
  scrollRailById("modal-recommendations-rail", direction);
}

async function loadDetailRecommendations(media, reqToken) {
  const recSection = document.getElementById("modal-recommendations-section");
  const recRail = document.getElementById("modal-recommendations-rail");
  if (!recSection || !recRail) return;

  recSection.classList.remove("hidden");
  recRail.innerHTML =
    '<div class="text-xs text-gray-500 p-3 flex items-center gap-2"><div class="w-4 h-4 border-2 border-brandCyan border-t-transparent rounded-full animate-spin"></div> Loading recommendations…</div>';

  let recommendations = [];
  try {
    recommendations = await fetchDesktopRecommendationsFor(media);
  } catch (err) {
    console.warn("[Omniverse] recommendations fetch failed:", err);
    recommendations = [];
  }

  if (reqToken !== detailModalRequestToken) return;

  const filtered = [];
  const seen = new Set();
  for (const rec of recommendations || []) {
    if (!rec) continue;
    if (
      media.tmdbId &&
      rec.tmdbId &&
      Number(rec.tmdbId) === Number(media.tmdbId)
    )
      continue;
    if (
      media.anilistId &&
      rec.anilistId &&
      Number(rec.anilistId) === Number(media.anilistId)
    )
      continue;
    const key =
      rec.id ||
      (rec.tmdbId ? `tmdb:${rec.tmdbId}` : "") ||
      (rec.anilistId ? `anilist:${rec.anilistId}` : "") ||
      `${rec.type || "media"}:${rec.title || "untitled"}`;
    if (seen.has(key)) continue;
    seen.add(key);
    filtered.push(rec);
    if (filtered.length >= 18) break;
  }

  if (!filtered.length) {
    recSection.classList.add("hidden");
    recRail.innerHTML = "";
    return;
  }

  recRail.innerHTML = "";
  enableHorizontalWheelScroll(recRail);
  appendMediaCards(recRail, filtered, 0, true);
}

// Detail Sheet Overlay Manager
async function openDetailModal(media) {
  const reqToken = ++detailModalRequestToken;
  // Clone so async enrichment never mutates source grid objects or old selection.
  state.selectedMedia = { ...(media || {}) };

  const modalPoster = document.getElementById("modal-poster");
  const modalBackdrop = document.getElementById("modal-backdrop-bg");
  const modalTitle = document.getElementById("modal-title");
  const modalOverview = document.getElementById("modal-overview");
  const modalYearChip = document.getElementById("modal-year-chip");
  const modalRatingChip = document.getElementById("modal-rating-chip");
  const typeChip = document.getElementById("modal-type-chip");
  const episodeSection = document.getElementById("modal-episodes-section");
  const playBtn = document.getElementById("modal-play-btn");
  const seasonSelector = document.getElementById("season-selector");
  const episodesGrid = document.getElementById("episodes-grid");
  const recSection = document.getElementById("modal-recommendations-section");
  const recRail = document.getElementById("modal-recommendations-rail");

  media = state.selectedMedia;

  // Reset stale modal content immediately.
  const modalLogo = document.getElementById("modal-logo");
  if (modalLogo) modalLogo.classList.add("hidden");
  if (modalTitle) modalTitle.classList.remove("hidden");
  if (seasonSelector) seasonSelector.innerHTML = "";
  if (episodesGrid) episodesGrid.innerHTML = "";
  if (recRail) recRail.innerHTML = "";
  if (recSection) recSection.classList.add("hidden");

  // Load initial fallback/passed data defensively
  if (modalPoster) modalPoster.src = media.poster;
  if (modalBackdrop)
    modalBackdrop.style.backgroundImage = `url('${media.backdrop || media.poster}')`;
  if (modalTitle) modalTitle.textContent = media.title;
  if (modalOverview) modalOverview.textContent = media.overview;
  if (modalYearChip) modalYearChip.textContent = media.year;
  if (modalRatingChip)
    modalRatingChip.innerHTML = `<i data-lucide="star" class="w-3.5 h-3.5 fill-amber-400"></i> ${media.rating}`;
  if (typeChip) typeChip.textContent = media.type.toUpperCase();

  // If TMDB is active, fetch deeper details dynamically from the live API.
  // Anime can use TMDB details too when it has a tmdbId.
  if (state.tmdbToken && media.tmdbId) {
    const tmdbEndpoint = media.type === "movie" ? "movie" : "tv";

    modalOverview.innerHTML = `
      <div class="flex items-center gap-2 text-brandCyan text-xs">
        <div class="w-3.5 h-3.5 rounded-full border border-current border-t-transparent animate-spin"></div>
        Fetching extended metadata from TMDB...
      </div>
    `;

    const details = await fetchTmdb(`${tmdbEndpoint}/${media.tmdbId}`, {
      append_to_response:
        "external_ids,credits,images,release_dates,content_ratings",
    });

    if (reqToken !== detailModalRequestToken) return;

    if (details) {
      const posterUrl = details.poster_path
        ? `https://image.tmdb.org/t/p/w500${details.poster_path}`
        : media.poster;
      const backdropUrl = details.backdrop_path
        ? `https://image.tmdb.org/t/p/original${details.backdrop_path}`
        : media.backdrop;

      if (modalPoster) modalPoster.src = posterUrl;
      if (modalBackdrop)
        modalBackdrop.style.backgroundImage = `url('${backdropUrl}')`;
      state.selectedMedia.poster = posterUrl;
      state.selectedMedia.backdrop = backdropUrl;
      if (details.external_ids) {
        state.selectedMedia.imdbId =
          details.external_ids.imdb_id || state.selectedMedia.imdbId || "";
        state.selectedMedia.tvdbId =
          details.external_ids.tvdb_id || state.selectedMedia.tvdbId || "";
        state.selectedMedia._playbackIdsChecked = true;
      }

      if (modalTitle)
        modalTitle.textContent = details.title || details.name || media.title;
      if (modalOverview)
        modalOverview.textContent =
          details.overview || "No description available.";

      const releaseDate = details.release_date || details.first_air_date || "";
      const year = releaseDate
        ? new Date(releaseDate).getFullYear()
        : media.year;
      if (modalYearChip) modalYearChip.textContent = year;
      state.selectedMedia.year = year;

      const runtime =
        details.runtime ||
        (details.episode_run_time && details.episode_run_time[0]) ||
        0;
      const h = Math.floor(runtime / 60);
      const m = runtime % 60;
      const runStr = runtime > 0 ? (h > 0 ? `${h}h ${m}m` : `${m}m`) : "";

      const modalRunChip = document.getElementById("modal-runtime-chip");
      if (modalRunChip) modalRunChip.textContent = runStr;

      const infoRuntime = document.getElementById("info-runtime");
      if (infoRuntime)
        infoRuntime.textContent = runtime > 0 ? runStr : "Unknown";

      const infoLang = document.getElementById("info-language");
      if (infoLang) infoLang.textContent = details.original_language || "EN";

      const infoRel = document.getElementById("info-release");
      if (infoRel) infoRel.textContent = releaseDate || "Unknown";

      const formatMoney = (amount) => {
        if (!amount) return "Unknown";
        return new Intl.NumberFormat("en-US", {
          style: "currency",
          currency: "USD",
          maximumFractionDigits: 0,
        }).format(amount);
      };

      const infoBudget = document.getElementById("info-budget");
      if (infoBudget) infoBudget.textContent = formatMoney(details.budget);

      const infoRev = document.getElementById("info-revenue");
      if (infoRev) infoRev.textContent = formatMoney(details.revenue);

      // Parse Director
      let director = "Unknown";
      if (details.credits && details.credits.crew) {
        const d = details.credits.crew.find((c) => c.job === "Director");
        if (d) director = d.name;
      }
      const modalDir = document.getElementById("modal-director");
      if (modalDir) modalDir.textContent = director;

      // Extract Content Rating
      let ageRating = "NR";
      if (details.release_dates && details.release_dates.results) {
        const us = details.release_dates.results.find(
          (r) => r.iso_3166_1 === "US",
        );
        if (us && us.release_dates && us.release_dates.length) {
          ageRating = us.release_dates[0].certification || "NR";
        }
      } else if (details.content_ratings && details.content_ratings.results) {
        const us = details.content_ratings.results.find(
          (r) => r.iso_3166_1 === "US",
        );
        if (us) ageRating = us.rating || "NR";
      }

      const contentRatingChip = document.getElementById(
        "modal-content-rating-chip",
      );
      if (contentRatingChip) contentRatingChip.textContent = ageRating;

      // Setup Logo
      const modalLogo = document.getElementById("modal-logo");
      const modalTitleText = document.getElementById("modal-title");
      if (
        details.images &&
        details.images.logos &&
        details.images.logos.length > 0
      ) {
        const engLogo =
          details.images.logos.find((l) => l.iso_639_1 === "en") ||
          details.images.logos[0];
        if (modalLogo) {
          modalLogo.src = `https://image.tmdb.org/t/p/w500${engLogo.file_path}`;
          modalLogo.classList.remove("hidden");
        }
        if (modalTitleText) modalTitleText.classList.add("hidden");
      } else {
        if (modalLogo) modalLogo.classList.add("hidden");
        if (modalTitleText) {
          modalTitleText.classList.remove("hidden");
          modalTitleText.textContent =
            details.title || details.name || media.title;
        }
      }

      // Populate Genres
      const genresList = details.genres
        ? details.genres.map((g) => g.name).join(" • ")
        : media.genres
          ? media.genres.join(" • ")
          : "";
      const genresContainer = document.getElementById("modal-genres");
      if (genresContainer) genresContainer.textContent = genresList;

      // Cast rail population
      const castRail = document.getElementById("modal-cast-rail");
      if (castRail && details.credits && details.credits.cast) {
        enableHorizontalWheelScroll(castRail);
        castRail.innerHTML = "";
        details.credits.cast.slice(0, 15).forEach((actor) => {
          const prof = actor.profile_path
            ? `https://image.tmdb.org/t/p/w185${actor.profile_path}`
            : "https://ui-avatars.com/api/?background=333&color=fff&name=" +
              encodeURIComponent(actor.name);
          castRail.innerHTML += `
            <div class="flex flex-col items-center gap-2 w-20 shrink-0 group">
              <img src="${prof}" class="w-16 h-16 rounded-full object-cover border-2 border-transparent group-hover:border-white/50 transition-all duration-300 shadow-lg">
              <div class="text-center">
                <p class="text-[10px] text-white font-bold leading-tight line-clamp-1">${actor.name}</p>
                <p class="text-[9px] text-gray-500 font-semibold line-clamp-1">${actor.character}</p>
              </div>
            </div>
          `;
        });
      }

      const rating = details.vote_average
        ? details.vote_average.toFixed(1)
        : media.rating;
      const ratingText = document.getElementById("modal-rating-text");
      if (ratingText) ratingText.textContent = rating;

      // Update seasons list if TV or Anime with seasons
      if (media.type === "tv" || (media.type === "anime" && details.seasons)) {
        const seasons = details.seasons || [];
        const selector = document.getElementById("season-selector");
        selector.innerHTML = "";

        const validSeasons = seasons.filter(
          (s) => s.season_number > 0 && s.episode_count > 0,
        );
        const seasonsToUse = validSeasons.length > 0 ? validSeasons : seasons;

        seasonsToUse.forEach((s) => {
          selector.innerHTML += `<option value="${s.season_number}">Season ${s.season_number} (${s.episode_count} Episodes)</option>`;
        });

        state.selectedMedia.seasons = seasonsToUse.length;
        state.selectedMedia.seasonsData = seasonsToUse;
      }
    } else {
      modalOverview.textContent = media.overview; // Restore on error
    }
  }

  if (reqToken !== detailModalRequestToken) return;

  if (media.type === "tv" || media.type === "anime") {
    episodeSection.classList.remove("hidden");
    playBtn.classList.add("hidden"); // Use episode cards to trigger streams

    if (media.type === "anime") {
      const selector = document.getElementById("season-selector");
      selector.innerHTML = "";
      const seasonCount = media.seasons || 1;
      for (let s = 1; s <= seasonCount; s++) {
        selector.innerHTML += `<option value="${s}">Season ${s}</option>`;
      }
    }

    await loadSeasonEpisodes();
  } else {
    episodeSection.classList.add("hidden");
    playBtn.classList.remove("hidden");
    playBtn.onclick = () => playStream(media);
  }

  document.getElementById("detail-modal").classList.remove("hidden");
  loadDetailRecommendations(state.selectedMedia, reqToken);
  lucide.createIcons();
}

function closeDetailModal() {
  // Invalidate pending async detail responses so they can't repaint stale content.
  detailModalRequestToken++;
  document.getElementById("detail-modal").classList.add("hidden");
}

function escapeHtml(s) {
  return (s || "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
}

function formatEpisodeRuntime(minutes) {
  if (!minutes || Number.isNaN(Number(minutes))) return "";
  return `${Math.max(1, Math.round(Number(minutes)))}m`;
}

function scrollRailById(railId, direction = 1) {
  const rail = document.getElementById(railId);
  if (!rail) return;
  const step = Math.max(240, Math.floor(rail.clientWidth * 0.75));
  rail.scrollBy({ left: direction * step, behavior: "smooth" });
}

function scrollEpisodesRail(direction = 1) {
  scrollRailById("episodes-grid", direction);
}

function scrollCastRail(direction = 1) {
  scrollRailById("modal-cast-rail", direction);
}

function enableHorizontalWheelScroll(el) {
  if (!el || el.dataset.horizontalWheelBound === "1") return;
  el.addEventListener(
    "wheel",
    (e) => {
      if (Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
      el.scrollLeft += e.deltaY;
      e.preventDefault();
    },
    { passive: false },
  );
  el.dataset.horizontalWheelBound = "1";
}

function appendEpisodeRow(grid, media, seasonVal, ep, title, extras = {}) {
  const stillPath = extras.stillPath || null;
  const overview = extras.overview || "";
  const runtime = formatEpisodeRuntime(extras.runtime);
  const thumb = stillPath
    ? `https://image.tmdb.org/t/p/w500${stillPath}`
    : media.backdrop ||
      media.poster ||
      "https://ui-avatars.com/api/?background=111&color=fff&name=Episode";

  const epRow = document.createElement("button");
  epRow.dataset.season = String(seasonVal);
  epRow.dataset.episode = String(ep);
  epRow.className =
    "group w-[300px] shrink-0 overflow-hidden rounded-xl border border-white/10 bg-black/30 text-left backdrop-blur-md transition-all duration-200 hover:-translate-y-0.5 hover:border-white/25 hover:bg-white/[0.08]";
  epRow.onclick = () => playStream(media, seasonVal, ep);
  epRow.innerHTML = `
    <div class="relative aspect-video w-full overflow-hidden">
      <img src="${thumb}" alt="${escapeHtml(title)}" class="h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.03]" loading="lazy" onerror="this.onerror=null; this.src='https://ui-avatars.com/api/?background=111&color=fff&name=Episode';">
      <span class="absolute left-2 top-2 rounded-full bg-black/70 px-2 py-0.5 text-[10px] font-black text-white">E${ep}</span>
      <span class="absolute right-2 bottom-2 rounded-full bg-black/70 px-2 py-0.5 text-[10px] font-bold text-white/90">${runtime || "--"}</span>
      <div class="absolute right-2 top-2 flex h-7 w-7 items-center justify-center rounded-full bg-black/60 text-white/90 transition-colors group-hover:bg-brandCyan/80">
        <i data-lucide="play" class="h-3.5 w-3.5 fill-current"></i>
      </div>
    </div>
    <div class="p-3">
      <p class="line-clamp-1 text-sm font-extrabold text-white">${escapeHtml(title)}</p>
      <p class="mt-1 line-clamp-2 text-xs text-gray-400">${escapeHtml(overview || "No description available.")}</p>
    </div>
  `;
  grid.appendChild(epRow);
}

async function loadSeasonEpisodes() {
  const media = state.selectedMedia;
  const seasonSelect = document.getElementById("season-selector");
  const seasonVal = parseInt(seasonSelect.value) || 1;
  const grid = document.getElementById("episodes-grid");
  enableHorizontalWheelScroll(grid);
  grid.innerHTML = "";

  // Anime: pull the real episode count + titles from AllAnime/AniList.
  if (media.type === "anime" && window.OmniAnime) {
    grid.innerHTML =
      '<div class="text-xs text-gray-500 p-3 flex items-center gap-2"><div class="w-4 h-4 border-2 border-brandCyan border-t-transparent rounded-full animate-spin"></div> Loading episodes…</div>';
    let count = media.episodesTotal || 0;
    let meta = {};
    try {
      const res = await window.OmniAnime.fetchEpisodes(media, seasonVal);
      count = res.count || count;
      meta = res.meta || {};
    } catch (e) {
      console.warn("[Omniverse] fetchEpisodes failed:", e);
    }
    grid.innerHTML = "";
    if (count <= 0) {
      grid.innerHTML =
        '<div class="text-xs text-gray-500 p-3">No episodes found for this season.</div>';
      return;
    }
    for (let ep = 1; ep <= count; ep++) {
      const title = (meta[ep] && meta[ep].title) || `Episode ${ep}`;
      appendEpisodeRow(grid, media, seasonVal, ep, title, {
        overview: (meta[ep] && meta[ep].overview) || "",
      });
    }
    lucide.createIcons();
    return;
  }

  // Dynamic TMDB TV Series Episode Loading!
  if (state.tmdbToken && media.tmdbId && media.type === "tv") {
    grid.innerHTML =
      '<div class="text-xs text-gray-500 p-3 flex items-center gap-2"><div class="w-4 h-4 border-2 border-brandCyan border-t-transparent rounded-full animate-spin"></div> Loading season episodes from TMDB…</div>';

    const seasonData = await fetchTmdb(
      `tv/${media.tmdbId}/season/${seasonVal}`,
    );
    grid.innerHTML = "";

    if (seasonData && seasonData.episodes && seasonData.episodes.length > 0) {
      seasonData.episodes.forEach((ep) => {
        appendEpisodeRow(
          grid,
          media,
          seasonVal,
          ep.episode_number,
          ep.name || `Episode ${ep.episode_number}`,
          {
            stillPath: ep.still_path,
            overview: ep.overview,
            runtime: ep.runtime,
          },
        );
      });
      lucide.createIcons();
      return;
    }
  }

  // Fallback Movies / TV (vidsrc-embed path) — unchanged.
  let epCount = 10;
  if (media.episodesPerSeason && media.episodesPerSeason[seasonVal - 1]) {
    epCount = media.episodesPerSeason[seasonVal - 1];
  }
  for (let ep = 1; ep <= epCount; ep++) {
    appendEpisodeRow(grid, media, seasonVal, ep, `Episode ${ep}`, {
      overview: "Episode information unavailable.",
    });
  }
  lucide.createIcons();
}

// Integrated Secure Webview Playback Launcher
// Ordered stream server list — shared by the player dropdown and auto-fallback.
// Primary domains match the mobile apps (vidsrc-embed.* / *.su) — these stay
// reachable where the older vidsrc.me/.to domains are ISP-blocked. Alternate
// providers follow as auto-fallback if the vidsrc infra is unreachable.
const STREAM_SERVERS = [
  { name: "VSEmbed RU", domain: "vsembed.ru", icon: "🔴" },
  { name: "VSEmbed SU", domain: "vsembed.su", icon: "🟠" },
  { name: "VidSrcMe RU", domain: "vidsrcme.ru", icon: "🟡" },
  { name: "2Embed", domain: "2embed.cc", icon: "🎥" },
  { name: "SmashyStream", domain: "embed.smashystream.com", icon: "💥" },
  { name: "AutoEmbed", domain: "autoembed.cc", icon: "🔥" },
  { name: "SuperEmbed", domain: "multiembed.mov", icon: "⚡" },
];

// ===========================================================================
// Chromeless VidSrc resolver — ported from Android VidsrcResolveScreen/WebGuards.
// Loads the embed in a managed <webview>, defeats iframe sandboxing + ad
// overlays, walks embed → cloudnestra /rcp/<hash>, auto-clicks play, and lets
// the stream play in-place with the provider's chrome stripped away.
// ===========================================================================
const VIDSRC_EMBED_DOMAINS = ["vsembed.ru", "vsembed.su", "vidsrcme.ru"];

// --- Injected JS guard payloads (verbatim from WebGuards.kt) ---------------
const WG_UNSANDBOX = String.raw`
(function () {
  if (window.__omniplayUnsandbox) return; window.__omniplayUnsandbox = true;
  try {
    var origSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      try { if (name && String(name).toLowerCase() === 'sandbox') return; } catch (_) {}
      return origSetAttribute.apply(this, arguments);
    };
  } catch (_) {}
  try {
    var sandboxDesc = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'sandbox');
    if (sandboxDesc && sandboxDesc.set) {
      Object.defineProperty(HTMLIFrameElement.prototype, 'sandbox', {
        configurable: true, enumerable: true,
        get: function () { try { return sandboxDesc.get.call(this); } catch (_) { return null; } },
        set: function () {}
      });
    }
  } catch (_) {}
  var unsandbox = function () {
    try {
      var frames = document.querySelectorAll('iframe[sandbox]');
      for (var i = 0; i < frames.length; i++) {
        var f = frames[i];
        if (f.getAttribute('data-omniplay-unsandboxed') === '1') { if (f.hasAttribute('sandbox')) { try { f.removeAttribute('sandbox'); } catch (_) {} } continue; }
        f.setAttribute('data-omniplay-unsandboxed', '1');
        try { f.removeAttribute('sandbox'); } catch (_) {}
        try { var src = f.getAttribute('src'); if (src) { f.setAttribute('src', 'about:blank'); f.setAttribute('src', src); } } catch (_) {}
      }
    } catch (_) {}
  };
  unsandbox();
  try { setInterval(unsandbox, 500); } catch (_) {}
  try { new MutationObserver(unsandbox).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['sandbox'] }); } catch (_) {}
})();
`;

const WG_GUARD = String.raw`
(function () {
  if (window.__omniplayGuards) return; window.__omniplayGuards = true;
  try { var st = document.createElement('style'); st.innerHTML = '* { outline: none !important; }'; document.documentElement.appendChild(st); } catch (_) {}
  try { window.open = function () { return null; }; } catch (_) {}
  var noop = function () {}; try { window.alert = noop; window.confirm = function(){return false;}; window.prompt = function(){return null;}; } catch (_) {}
  try { var o = window.addEventListener; window.addEventListener = function (t, l, op) { if (t==='beforeunload'||t==='unload') return; o.apply(this, arguments); }; } catch (_) {}
  var safeHosts = ['vidcore','created.app','vidsrc','vidsrc-embed','cloudnestra','cloudorchestra','vsembed','vsrc.','vidsrcme','about:','localhost','127.0.0.1','cdn','2embed','streamsrcs','embed.su','smashystream','autoembed','multiembed','streamtape','streamlare','doodstream','mixdrop','vidplay','filemoon','upstream','fembed','streamhide','mp4upload','streamsb','voe.sx','streamwish','vidcloud','youtube','workers.dev','instafashion662','ferocitycandour','cinezo','notyourtype.dad','1shows.app','vidlink','vidnest','vidrock','vidzee'];
  var isAdHost = function (url) { try { if (!url) return false; var h = new URL(url, location.href).hostname.toLowerCase(); return !safeHosts.some(function(s){return h.indexOf(s)>=0;}); } catch (_) { return false; } };
  var adTokens = ['ads','ad-','analytics','doubleclick','googletagmanager','googletagservices','pagead','popunder','popcash','propellerads','adservice','adsco','rtmark','profitable','histats','usrpubtrk','adexchangeclear','realizationnewestfangs','unbrownunflat','sixmossin','malocacomals','cloudflareinsights','videasy','bvtpk','b7510','adx1','intelligenceadx','yandex','tmstr.','click','track','redirect','pop'];
  var isAdSrc = function (src) { if (!src) return false; var s = String(src).toLowerCase(); if (safeHosts.some(function(h){return s.indexOf(h)>=0;})) return false; return adTokens.some(function(t){return s.indexOf(t)>=0;}); };
  try { var a = window.location.assign.bind(window.location); var r = window.location.replace.bind(window.location);
    window.location.assign = function(u){ if (!isAdHost(u)) a(u); }; window.location.replace = function(u){ if (!isAdHost(u)) r(u); }; } catch (_) {}
  var fixAnchors = function () { document.querySelectorAll('a[target]').forEach(function(a){ var t=a.getAttribute('target'); if (t==='_blank'||t==='_top'||t==='_parent') a.removeAttribute('target'); }); };
  var stripAds = function () { document.querySelectorAll('iframe').forEach(function(f){ if (isAdSrc(f.src)) f.remove(); }); document.querySelectorAll('script').forEach(function(s){ if (isAdSrc(s.src)) s.remove(); }); fixAnchors(); };
  stripAds();
  try { new MutationObserver(stripAds).observe(document.documentElement, { childList: true, subtree: true }); } catch (_) {}
  document.addEventListener('click', function (e) { var a = e.target && e.target.closest && e.target.closest('a[href]'); if (a && isAdHost(a.href)) { e.preventDefault(); e.stopPropagation(); } }, true);
  setInterval(function () { var divs = document.querySelectorAll('div'); var sw = window.innerWidth, sh = window.innerHeight;
    for (var i=0;i<divs.length;i++){ var d=divs[i]; var st2=window.getComputedStyle(d); if (st2.position==='absolute'||st2.position==='fixed'){ var z=parseInt(st2.zIndex,10); if (z>99){ var w=d.offsetWidth,h=d.offsetHeight; if (w>sw*0.5&&h>sh*0.5){ if (!d.querySelector('video, iframe, canvas, img') && d.innerText.trim().length<50) d.remove(); } } } } }, 500);
})();
`;

const WG_EMBED_PROBE = String.raw`
(function () {
  try {
    var html = document.documentElement.outerHTML || '';
    var iframeMatch = html.match(/<iframe[^>]+src=["']([^"']+)["']/i);
    var iframeSrc = iframeMatch ? iframeMatch[1] : '';
    var simpleRe = /data-hash=["']([^"']+)["']/g;
    var seen = {}, servers = [], m;
    var nameRe = /data-hash=["']([^"']+)["'][^>]*>([\s\S]*?)<\/div>/g;
    while ((m = nameRe.exec(html)) !== null) { var hash=m[1]; if (!hash||seen[hash]) continue; seen[hash]=true; var name=(m[2]||'').replace(/<[^>]*>/g,'').trim(); servers.push({name:name,hash:hash}); }
    if (servers.length === 0) { while ((m = simpleRe.exec(html)) !== null) { if (!seen[m[1]]) { seen[m[1]]=true; servers.push({name:'',hash:m[1]}); } } }
    var bodyText = (document.body && document.body.innerText) || '';
    var hasChallenge = /just a moment/i.test(document.title) || /cf-chl|cf_chl|checking your browser/i.test(bodyText) || /enable javascript and cookies/i.test(bodyText);
    var hasVideo = !!document.querySelector('video') || !!document.querySelector('iframe[allowfullscreen], iframe[src*="player"], iframe[src*="/e/"], iframe[src*="embed"]');
    return JSON.stringify({ title: document.title||'', url: location.href, iframeSrc: iframeSrc, servers: servers, hasChallenge: hasChallenge, hasVideo: hasVideo });
  } catch (e) { return JSON.stringify({ error: String(e) }); }
})();
`;

const WG_PLAYER_PROBE = String.raw`
(function () {
  try {
    var hasPlayButton = !!document.querySelector('#pl_but,.fa-play,[id*=play]');
    var iframeLoaded = !!document.querySelector('iframe[src*="prorcp"], iframe#player_iframe');
    var bodyText = (document.body && document.body.innerText) || '';
    var hasChallenge = /just a moment/i.test(document.title) || /cf-chl|cf_chl|checking your browser/i.test(bodyText) || /enable javascript and cookies/i.test(bodyText);
    var hasTurnstile = !!document.querySelector('.cf-turnstile, [data-sitekey]');
    var hasRcpToken = /[?&]_rcp=/.test(location.href);
    return JSON.stringify({ title: document.title||'', url: location.href, hasPlayButton: hasPlayButton, iframeLoaded: iframeLoaded, hasChallenge: hasChallenge, hasTurnstile: hasTurnstile, hasRcpToken: hasRcpToken });
  } catch (e) { return JSON.stringify({ error: String(e) }); }
})();
`;

const WG_CLICK_PLAY =
  "(function(){var b=document.querySelector('#pl_but,.fa-play,[id*=play]');if(b)b.click();})();";

let vidsrcResolver = null;

// Electron <webview> ignores percentage height (falls back to ~150px). The
// player overlay is a full-viewport fixed layer, so size the webview to the
// window in explicit pixels and keep it in sync on resize.
function sizeWebviewToWindow(webview) {
  const apply = () => {
    webview.style.setProperty("position", "absolute", "important");
    webview.style.setProperty("top", "0", "important");
    webview.style.setProperty("left", "0", "important");
    webview.style.setProperty("right", "0", "important");
    webview.style.setProperty("bottom", "0", "important");
    webview.style.setProperty("z-index", "1", "important");

    const isWebview =
      webview &&
      webview.tagName &&
      String(webview.tagName).toLowerCase() === "webview";

    if (isWebview) {
      const container = document.getElementById("webview-container");
      const rect = container
        ? container.getBoundingClientRect()
        : { width: window.innerWidth, height: window.innerHeight };
      const width = Math.max(1, Math.floor(rect.width || window.innerWidth));
      const height = Math.max(1, Math.floor(rect.height || window.innerHeight));

      // Electron webview behaves best with explicit pixel sizing.
      webview.style.setProperty("width", width + "px", "important");
      webview.style.setProperty("height", height + "px", "important");
      webview.style.setProperty("min-width", width + "px", "important");
      webview.style.setProperty("min-height", height + "px", "important");
      webview.style.setProperty("max-width", width + "px", "important");
      webview.style.setProperty("max-height", height + "px", "important");

      webview.removeAttribute("width");
      webview.removeAttribute("height");
      webview.removeAttribute("autosize");
      webview.removeAttribute("minwidth");
      webview.removeAttribute("minheight");
      webview.removeAttribute("maxwidth");
      webview.removeAttribute("maxheight");
    } else {
      // Standard iframe path (VidCore) should mirror provider docs.
      webview.style.setProperty("width", "100%", "important");
      webview.style.setProperty("height", "100%", "important");
      webview.style.setProperty("min-width", "100%", "important");
      webview.style.setProperty("min-height", "100%", "important");
      webview.style.setProperty("max-width", "100%", "important");
      webview.style.setProperty("max-height", "100%", "important");
    }
  };

  apply();
  requestAnimationFrame(apply);

  if (webview.__omniResize) {
    window.removeEventListener("resize", webview.__omniResize);
  }
  webview.__omniResize = apply;
  window.addEventListener("resize", apply);
}
function unsizeWebview(webview) {
  if (webview && webview.__omniResize) {
    window.removeEventListener("resize", webview.__omniResize);
    webview.__omniResize = null;
  }
}

function buildEmbedUrls(media, season, episode, forceDomain) {
  const pref = VIDSRC_EMBED_DOMAINS.includes(forceDomain)
    ? forceDomain
    : VIDSRC_EMBED_DOMAINS.includes(state.vidsrcDomain)
      ? state.vidsrcDomain
      : DEFAULT_VIDSRC_DOMAIN;
  const ordered = VIDSRC_EMBED_DOMAINS.includes(pref)
    ? [pref, ...VIDSRC_EMBED_DOMAINS.filter((d) => d !== pref)]
    : [pref, ...VIDSRC_EMBED_DOMAINS];
  const path = media.type === "movie" ? "/embed/movie" : "/embed/tv";
  const q =
    media.type === "movie"
      ? `tmdb=${media.tmdbId}&autoplay=1`
      : `tmdb=${media.tmdbId}&season=${season}&episode=${episode}&autonext=1&autoplay=1`;
  return ordered.map((d) => `https://${d}${path}?${q}`);
}

// The old chromeless resolver walked VidSrc internals and navigated directly to
// provider /rcp pages. That worked only for one VidSrc generation and often left
// a stripped/black shell once providers changed nested player hosts. Use a single
// embedded-player pipeline for every server instead: load the provider's own
// embed, allow the real nested player hosts, probe for a playable surface, and
// fail over when a page loads but stays blank.
// Give each embed source up to ~30s to become playable, then auto-failover.
const EMBED_LOAD_TIMEOUT_MS = 30000;
const EMBED_HEALTH_DELAY_MS = 4500;
const EMBED_HEALTH_RECHECK_MS = 4500;
const EMBED_HEALTH_GRACE_MS = 30000;

const EMBED_HEALTH_PROBE = String.raw`
(function () {
  try {
    var body = document.body;
    var bodyText = body ? (body.innerText || '') : '';
    var lowerText = bodyText.toLowerCase();
    var frames = Array.prototype.slice.call(document.querySelectorAll('iframe[src], object, embed'));
    var videos = Array.prototype.slice.call(document.querySelectorAll('video'));
    var visibleFrames = frames.filter(function (f) {
      try { var r = f.getBoundingClientRect(); return r.width > 40 && r.height > 40; } catch (_) { return true; }
    });
    var visibleVideos = videos.filter(function (v) {
      try { var r = v.getBoundingClientRect(); return r.width > 40 && r.height > 40; } catch (_) { return true; }
    });
    var playerLike = false;
    var els = document.querySelectorAll('[id], [class], button, [role="button"], video, iframe');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var sig = String((el.id || '') + ' ' + (el.className || '') + ' ' + (el.tagName || '')).toLowerCase();
      if (/(player|video|jwplayer|plyr|vjs|play)/.test(sig)) { playerLike = true; break; }
    }
    var hasChallenge = /just a moment|cf-chl|cf_chl|checking your browser|enable javascript and cookies|turnstile|captcha/.test(String(document.title || '').toLowerCase() + ' ' + lowerText);
    var hasHardError = /(404|not found|unavailable|no sources|source unavailable|failed to load|access denied|server error|temporarily down)/.test(lowerText);
    var hasPlayableSurface = visibleFrames.length > 0 || visibleVideos.length > 0 || playerLike;
    var blank = bodyText.trim().length < 15 && visibleFrames.length === 0 && visibleVideos.length === 0 && !playerLike;
    return JSON.stringify({
      title: document.title || '',
      url: location.href,
      textLength: bodyText.trim().length,
      frameCount: frames.length,
      visibleFrameCount: visibleFrames.length,
      videoCount: videos.length,
      visibleVideoCount: visibleVideos.length,
      hasPlayableSurface: hasPlayableSurface,
      hasChallenge: hasChallenge,
      hasHardError: hasHardError,
      blank: blank
    });
  } catch (e) {
    return JSON.stringify({ error: String(e), blank: true });
  }
})();
`;

function playbackTitle(media, season, episode) {
  return media.type === "movie"
    ? `${media.title} (Movie)`
    : `${media.title} — S${season || 1} E${episode || 1}`;
}

function orderedStreamServers(forceDomain = null) {
  const servers = STREAM_SERVERS.slice();
  const preferred = forceDomain || state.vidsrcDomain || DEFAULT_VIDSRC_DOMAIN;
  const idx = servers.findIndex((s) => s.domain === preferred);
  if (idx >= 0) return [servers[idx], ...servers.filter((_, i) => i !== idx)];
  if (preferred) {
    return [{ name: preferred, domain: preferred, icon: "▶️" }, ...servers];
  }
  return servers;
}

function compactUniqueUrls(urls) {
  const seen = new Set();
  return urls.filter((url) => {
    if (!url || seen.has(url)) return false;
    seen.add(url);
    return true;
  });
}

function providerUrlsForServer(server, media, season, episode) {
  const tmdbId = media && media.tmdbId ? encodeURIComponent(media.tmdbId) : "";
  if (!tmdbId) return [];

  const imdbId = media && media.imdbId ? encodeURIComponent(media.imdbId) : "";
  const domain = server.domain;
  const s = encodeURIComponent(season || 1);
  const e = encodeURIComponent(episode || 1);
  const isMovie = media.type === "movie";

  if (
    domain.includes("vsembed") ||
    domain.includes("vidsrcme.ru") ||
    domain.includes("vidsrc-embed") ||
    domain.includes("vidsrcme.su") ||
    domain.includes("vsrc.su") ||
    domain.includes("vidsrc.net")
  ) {
    return compactUniqueUrls([
      isMovie
        ? `https://${domain}/embed/movie/${tmdbId}`
        : `https://${domain}/embed/tv/${tmdbId}/${s}/${e}`,
    ]);
  }

  if (domain.includes("multiembed")) {
    return compactUniqueUrls([
      isMovie
        ? `https://multiembed.mov/?video_id=${tmdbId}&tmdb=1`
        : `https://multiembed.mov/?video_id=${tmdbId}&tmdb=1&s=${s}&e=${e}`,
    ]);
  }

  if (domain.includes("autoembed")) {
    return compactUniqueUrls([
      isMovie
        ? `https://autoembed.cc/embed/player.php?id=${tmdbId}`
        : `https://autoembed.cc/embed/player.php?id=${tmdbId}&s=${s}&e=${e}`,
    ]);
  }

  if (domain.includes("2embed")) {
    return compactUniqueUrls([
      isMovie && imdbId ? `https://www.2embed.cc/embed/${imdbId}` : "",
      isMovie ? `https://www.2embed.cc/embed/${tmdbId}` : "",
      !isMovie && imdbId
        ? `https://www.2embed.cc/embedtv/${imdbId}&s=${s}&e=${e}`
        : "",
      !isMovie ? `https://www.2embed.cc/embedtv/${tmdbId}&s=${s}&e=${e}` : "",
      isMovie && imdbId ? `https://2embed.cc/embed/${imdbId}` : "",
      isMovie ? `https://2embed.cc/embed/${tmdbId}` : "",
    ]);
  }

  if (domain.includes("smashy")) {
    return compactUniqueUrls([
      isMovie
        ? `https://embed.smashystream.com/playere.php?tmdb=${tmdbId}`
        : `https://embed.smashystream.com/playere.php?tmdb=${tmdbId}&season=${s}&ep=${e}`,
    ]);
  }

  const path = isMovie ? "/embed/movie" : "/embed/tv";
  const query = isMovie
    ? `tmdb=${tmdbId}&autoplay=1`
    : `tmdb=${tmdbId}&season=${s}&episode=${e}&autonext=1&autoplay=1`;
  const primary = `https://${domain}${path}?${query}`;
  const pathStyle = isMovie
    ? `https://${domain}${path}/${tmdbId}?autoplay=1`
    : `https://${domain}${path}/${tmdbId}/${s}/${e}?autonext=1&autoplay=1`;
  return compactUniqueUrls([primary, domain === "vidsrc.net" ? pathStyle : ""]);
}

function buildEmbedAttemptQueue(media, season, episode, forceDomain = null) {
  return orderedStreamServers(forceDomain).flatMap((server) =>
    providerUrlsForServer(server, media, season, episode).map((url, idx) => ({
      server,
      domain: server.domain,
      url,
      label: idx === 0 ? server.name : `${server.name} mirror ${idx + 1}`,
    })),
  );
}

function createEmbedStatusOverlay() {
  const el = document.createElement("div");
  el.className =
    "absolute inset-0 z-30 flex flex-col items-center justify-center gap-4 text-center px-8 bg-black/35 pointer-events-none transition-opacity duration-300";
  el.innerHTML = `
    <div class="w-10 h-10 rounded-full border-2 border-brandCyan border-t-transparent animate-spin"></div>
    <div class="space-y-1">
      <p class="text-sm text-white font-semibold" data-status-title>Loading player…</p>
      <p class="text-[11px] text-gray-400 max-w-lg" data-status-detail>Preparing embed</p>
    </div>`;
  return el;
}

// Legacy entry point retained for any older click handlers. VidSrc now uses the same
// provider-embed queue as every other server.
function playStreamResolved(media, season, episode, forceDomain) {
  playStreamEmbed(media, season, episode, forceDomain);
}

async function ensurePlaybackIds(media) {
  if (
    !media ||
    !state.tmdbToken ||
    !media.tmdbId ||
    media._playbackIdsChecked
  ) {
    return media;
  }
  media._playbackIdsChecked = true;
  const endpoint = media.type === "movie" ? "movie" : "tv";
  const details = await fetchTmdb(`${endpoint}/${media.tmdbId}`, {
    append_to_response: "external_ids",
  });
  const ids = details && details.external_ids;
  if (ids) {
    if (ids.imdb_id) media.imdbId = ids.imdb_id;
    if (ids.tvdb_id) media.tvdbId = ids.tvdb_id;
  }
  return media;
}

// Router: anime (including TMDB titles detected as anime) → direct
// AllAnime stream; movies/TV → unified embedded provider queue.
async function playStream(
  media,
  season = null,
  episode = null,
  forceDomain = null,
) {
  const animeCandidate = isLikelyAnime(media);
  if (animeCandidate) {
    if (window.OmniAnime) {
      playAnimeStream(media, episode || 1, season || 1);
      return;
    }

    // Keep anime on the ani-cli path: if the anime module failed to load,
    // surface that explicitly instead of dropping to generic embed providers.
    captureReturnToDetailContext(media, season || 1, episode || 1);
    closeDetailModal();
    const overlay = document.getElementById("player-overlay");
    if (overlay) overlay.classList.remove("hidden");
    showPlayerStatus(
      `<i data-lucide="wifi-off" class="w-12 h-12 text-brandCyan"></i>
       <h3 class="text-lg font-bold text-white">Anime module unavailable</h3>
       <p class="text-sm text-gray-400 max-w-md">AniList/AllAnime failed to load. Reload the app and try again.</p>`,
    );
    return;
  }

  await ensurePlaybackIds(media);
  playStreamEmbed(media, season, episode, forceDomain);
}

function playStreamEmbed(
  media,
  season = null,
  episode = null,
  forceDomain = null,
) {
  captureReturnToDetailContext(media, season, episode);
  closeDetailModal();

  // Direct-player progress tracker applies to anime direct streams only; stop and
  // flush it before switching to an embed-based playback session.
  stopActiveDirectPlayback({ saveFinal: true });

  // Match mobile behavior: seed non-anime entries into Continue Watching as soon
  // as playback is launched, so the shelf reflects the current title immediately.
  if (media && normalizeWatchType(media.type) !== "anime") {
    recordWatchProgress(
      media,
      10_000,
      3_600_000,
      {
        seasonNumber: season,
        episodeNumber: episode,
      },
      { syncRemote: true },
    );
  }

  if (vidsrcResolver) {
    vidsrcResolver.cancelled = true;
    vidsrcResolver = null;
  }
  if (state.activeEmbedSession && state.activeEmbedSession.cancel) {
    state.activeEmbedSession.cancel();
  }
  if (state.activeHls) {
    try {
      state.activeHls.destroy();
    } catch (_) {}
    state.activeHls = null;
  }

  const titleEl = document.getElementById("player-stream-title");
  if (titleEl) titleEl.textContent = playbackTitle(media, season, episode);
  populateServerDropdown(media, season, episode);

  const container = document.getElementById("webview-container");
  unsizeWebview(state.activeWebview);
  state.activeWebview = null;
  container.innerHTML = "";

  const attempts = buildEmbedAttemptQueue(media, season, episode, forceDomain);
  state.currentPlayback = { media, season, episode, forceDomain };
  state.triedDomains = [];

  document.getElementById("player-overlay").classList.remove("hidden");

  if (attempts.length === 0) {
    showPlayerStatus(
      `<i data-lucide="alert-triangle" class="w-12 h-12 text-brandCyan"></i>
       <h3 class="text-lg font-bold text-white">No embed URL could be built</h3>
       <p class="text-sm text-gray-400 max-w-md">This title is missing the metadata id needed by the stream providers.</p>`,
    );
    return;
  }

  // Use iframe path for all providers to keep embed sizing/rendering consistent.
  const useElectronWebview = false;
  const webview = document.createElement("iframe");
  webview.id = "active-player-webview";
  webview.className = "webview-player";
  webview.setAttribute("allowfullscreen", "true");
  if (useElectronWebview) {
    webview.setAttribute("partition", "persist:player");
    webview.setAttribute(
      "webpreferences",
      "allowRunningInsecureContent=yes, autoplayPolicy=no-user-gesture-required",
    );
    webview.style.setProperty("width", "100%", "important");
    webview.style.setProperty("height", "100%", "important");
  } else {
    webview.setAttribute("width", "100%");
    webview.setAttribute("height", "100%");
    webview.setAttribute(
      "allow",
      "autoplay; fullscreen; picture-in-picture; encrypted-media",
    );

    webview.setAttribute("referrerpolicy", "origin-when-cross-origin");
    webview.setAttribute("frameborder", "0");
    webview.setAttribute("scrolling", "no");
  }

  const statusEl = createEmbedStatusOverlay();
  container.appendChild(webview);
  container.appendChild(statusEl);
  sizeWebviewToWindow(webview);
  state.activeWebview = webview;

  const parseJson = (value) => {
    try {
      return JSON.parse(value);
    } catch (_) {
      return null;
    }
  };

  let webviewDomReady = false;

  const session = {
    attempts,
    index: 0,
    webview,
    statusEl,
    loadTimer: null,
    healthTimer: null,
    failTimer: null,
    cancelled: false,
    switching: false,
    ready: false,
    token: 0,
    startedAt: 0,
    currentAttempt: null,
    clearTimers() {
      for (const key of ["loadTimer", "healthTimer", "failTimer"]) {
        if (this[key]) clearTimeout(this[key]);
        this[key] = null;
      }
    },
    cancel() {
      this.cancelled = true;
      this.clearTimers();
    },
    showStatus(title, detail = "", spinning = true) {
      const titleNode = this.statusEl.querySelector("[data-status-title]");
      const detailNode = this.statusEl.querySelector("[data-status-detail]");
      const spinner = this.statusEl.querySelector(".animate-spin");
      if (titleNode) titleNode.textContent = title;
      if (detailNode) detailNode.textContent = detail;
      if (spinner) spinner.style.display = spinning ? "block" : "none";
      this.statusEl.style.visibility = "visible";
      this.statusEl.style.opacity = "1";
    },
    hideStatus() {
      this.statusEl.style.opacity = "0";
      this.statusEl.style.visibility = "hidden";
    },
    failCurrent(reason = "failed to load") {
      if (this.cancelled || this.switching) return;
      this.switching = true;
      this.ready = false;
      this.clearTimers();

      const failed = this.currentAttempt;
      const next = this.attempts[this.index + 1];
      if (!next) {
        this.cancelled = true;
        if (state.activeEmbedSession === this) state.activeEmbedSession = null;
        if (state.activeWebview === this.webview) {
          unsizeWebview(this.webview);
          state.activeWebview = null;
        }
        showPlayerStatus(
          `<i data-lucide="wifi-off" class="w-12 h-12 text-brandCyan"></i>
           <h3 class="text-lg font-bold text-white">All sources are unavailable</h3>
           <p class="text-sm text-gray-400 max-w-md">${failed ? failed.label : "The selected source"} ${reason}. Try again shortly, or choose another server manually.</p>`,
        );
        return;
      }

      this.showStatus(
        `${failed ? failed.label : "Source"} unavailable`,
        `Trying ${next.label}…`,
      );
      this.failTimer = setTimeout(() => {
        if (this.cancelled) return;
        this.index += 1;
        this.loadCurrent();
      }, 800);
    },
    loadCurrent() {
      if (this.cancelled) return;
      this.clearTimers();
      this.switching = false;
      this.ready = false;

      if (this.index >= this.attempts.length) {
        this.failCurrent("failed");
        return;
      }

      const attempt = this.attempts[this.index];
      this.currentAttempt = attempt;
      this.startedAt = Date.now();
      const token = ++this.token;
      state.triedDomains = this.attempts
        .slice(0, this.index + 1)
        .map((a) => a.domain);

      let host = attempt.url;
      try {
        host = new URL(attempt.url).host;
      } catch (_) {}
      this.showStatus(`Loading ${attempt.label}…`, host);

      try {
        webviewDomReady = false;
        this.webview.dataset.currentSrc = attempt.url;
        // Use iframe-style src assignment for both <webview> and <iframe>.
        // Calling webview.loadURL() before dom-ready can throw in Electron.
        this.webview.setAttribute("src", attempt.url);
      } catch (err) {
        this.failCurrent(err && err.message ? err.message : "failed");
        return;
      }

      this.loadTimer = setTimeout(() => {
        if (this.cancelled || this.token !== token || this.ready) return;
        this.failCurrent("timed out");
      }, EMBED_LOAD_TIMEOUT_MS);
    },
    scheduleHealth(delay = EMBED_HEALTH_DELAY_MS) {
      if (this.cancelled || this.ready) return;
      const token = this.token;
      if (this.healthTimer) clearTimeout(this.healthTimer);
      this.healthTimer = setTimeout(() => this.checkHealth(token), delay);
    },
    async checkHealth(token) {
      if (this.cancelled || this.ready || token !== this.token) return;
      if (typeof this.webview.executeJavaScript !== "function") {
        // Browser/Qt iframe fallback: cross-origin pages cannot be probed, so a
        // completed iframe load is the best available readiness signal.
        this.ready = true;
        this.clearTimers();
        this.hideStatus();
        return;
      }
      if (!webviewDomReady) {
        this.scheduleHealth(EMBED_HEALTH_RECHECK_MS);
        return;
      }
      const raw = await this.webview
        .executeJavaScript(EMBED_HEALTH_PROBE, true)
        .catch(() => null);
      const health = parseJson(raw);
      if (this.cancelled || this.ready || token !== this.token) return;

      const age = Date.now() - this.startedAt;
      if (!health) {
        if (age > EMBED_HEALTH_GRACE_MS) this.failCurrent("stayed blank");
        else this.scheduleHealth(EMBED_HEALTH_RECHECK_MS);
        return;
      }

      if (health.hasChallenge) {
        this.showStatus(
          "Waiting for provider verification…",
          "Cloudflare or Turnstile challenge detected",
        );
        if (age > EMBED_LOAD_TIMEOUT_MS)
          this.failCurrent("verification timed out");
        else this.scheduleHealth(EMBED_HEALTH_RECHECK_MS);
        return;
      }

      if (
        health.hasHardError ||
        (health.blank && age > EMBED_HEALTH_GRACE_MS)
      ) {
        this.failCurrent(
          health.hasHardError ? "reported an error" : "stayed blank",
        );
        return;
      }

      if (health.hasPlayableSurface) {
        this.ready = true;
        this.clearTimers();
        this.hideStatus();
        return;
      }

      if (age > EMBED_HEALTH_GRACE_MS) {
        this.failCurrent("did not expose a player");
      } else {
        this.showStatus(
          "Waiting for player…",
          "The provider page loaded; waiting for the nested player",
        );
        this.scheduleHealth(EMBED_HEALTH_RECHECK_MS);
      }
    },
  };

  state.activeEmbedSession = session;

  const runGuards = () => {
    if (typeof webview.executeJavaScript !== "function") return;
    if (!webviewDomReady) return;
    webview.executeJavaScript(WG_UNSANDBOX, true).catch(() => null);
    webview.executeJavaScript(WG_GUARD, true).catch(() => null);
  };

  webview.addEventListener("dom-ready", () => {
    webviewDomReady = true;
    sizeWebviewToWindow(webview);
    runGuards();
    session.scheduleHealth(EMBED_HEALTH_DELAY_MS);
  });
  webview.addEventListener("did-finish-load", () => {
    if (session.loadTimer) clearTimeout(session.loadTimer);
    session.loadTimer = null;
    sizeWebviewToWindow(webview);
    runGuards();
    session.scheduleHealth(EMBED_HEALTH_DELAY_MS);
  });
  webview.addEventListener("did-stop-loading", () => {
    sizeWebviewToWindow(webview);
    session.scheduleHealth(EMBED_HEALTH_DELAY_MS);
  });
  webview.addEventListener("did-fail-load", (e) => {
    if (!e.isMainFrame || e.errorCode === -3) return;
    session.failCurrent(e.errorDescription || `error ${e.errorCode}`);
  });
  webview.addEventListener("load", () => {
    sizeWebviewToWindow(webview);
    if (typeof webview.executeJavaScript !== "function") {
      session.ready = true;
      session.clearTimers();
      session.hideStatus();
    }
  });
  webview.addEventListener("crashed", () => session.failCurrent("crashed"));

  session.loadCurrent();

  if (window.electron && window.electron.showNotification) {
    window.electron.showNotification(
      "Streaming Live",
      `Loading ${attempts[0].label}`,
    );
  }
}

// Populate the custom dropdown servers list
function populateServerDropdown(media, season, episode) {
  const list = document.getElementById("server-dropdown-list");
  if (!list) return;

  const servers = STREAM_SERVERS;

  list.innerHTML = "";

  servers.forEach((srv) => {
    const btn = document.createElement("button");
    btn.className =
      "w-full text-left px-4 py-3 hover:bg-white/10 rounded-lg text-sm text-white font-medium flex items-center gap-3 transition cursor-pointer";
    btn.innerHTML = `<span>${srv.icon}</span> ${srv.name} <span class="text-[10px] text-gray-500 ml-auto">${srv.domain}</span>`;
    btn.onclick = () => {
      // Manual pick = fresh intent: restart the fallback chain from this server.
      state.triedDomains = [];
      playStream(media, season, episode, srv.domain);
    };
    list.appendChild(btn);
  });
}

// Auto-fallback: when a source's main frame fails to load (dead/unreachable
// host), automatically try the next server and keep the player informed instead
// of showing a silent black screen.
function setupWebviewFailObserver() {
  if (!window.electron || !window.electron.onWebviewLoadFailed) return;
  window.electron.onWebviewLoadFailed(({ errorCode, errorDesc }) => {
    const overlay = document.getElementById("player-overlay");
    if (!overlay || overlay.classList.contains("hidden")) return;

    if (state.activeEmbedSession && !state.activeEmbedSession.cancelled) {
      state.activeEmbedSession.failCurrent(errorDesc || `error ${errorCode}`);
      return;
    }

    const ctx = state.currentPlayback;
    if (!ctx) return;

    const tried = state.triedDomains || [];
    const next = STREAM_SERVERS.find((s) => !tried.includes(s.domain));

    if (next) {
      showPlayerStatus(
        `<div class="w-10 h-10 rounded-full border-2 border-brandCyan border-t-transparent animate-spin"></div>
         <p class="text-sm text-gray-300 font-medium max-w-md">Source unavailable (${errorDesc || "error " + errorCode}). Trying <span class="text-white font-semibold">${next.name}</span>…</p>`,
      );
      setTimeout(() => {
        playStream(ctx.media, ctx.season, ctx.episode, next.domain);
      }, 700);
    } else {
      showPlayerStatus(
        `<i data-lucide="wifi-off" class="w-12 h-12 text-brandCyan"></i>
         <h3 class="text-lg font-bold text-white">All sources are unavailable</h3>
         <p class="text-sm text-gray-400 max-w-md">Every stream server failed to load — this is usually a temporary outage on the source's side. Try again shortly, or pick a server manually from the Servers menu.</p>`,
      );
    }
  });
}

// Render a centered status/message inside the player webview container.
function showPlayerStatus(innerHtml) {
  const container = document.getElementById("webview-container");
  if (!container) return;
  unsizeWebview(state.activeWebview);
  state.activeWebview = null;
  container.innerHTML = `
    <div class="absolute inset-0 flex flex-col items-center justify-center gap-4 text-center px-8">
      ${innerHtml}
    </div>`;
  if (window.lucide) lucide.createIcons();
}

function playAnimeEmbed(container, media, episode, src) {
  if (!container || !src || !src.url) return;
  unsizeWebview(state.activeWebview);
  state.activeWebview = null;
  container.innerHTML = "";

  const frame = document.createElement("iframe");
  frame.id = "active-player-webview";
  frame.className = "webview-player";
  frame.setAttribute("allowfullscreen", "true");
  frame.setAttribute(
    "allow",
    "autoplay; fullscreen; picture-in-picture; encrypted-media",
  );
  frame.setAttribute("referrerpolicy", "origin-when-cross-origin");
  frame.setAttribute("frameborder", "0");
  frame.setAttribute("scrolling", "no");
  frame.setAttribute("width", "100%");
  frame.setAttribute("height", "100%");
  frame.setAttribute("src", src.url);

  container.appendChild(frame);
  sizeWebviewToWindow(frame);
  state.activeWebview = frame;

  if (window.electron && window.electron.showNotification) {
    window.electron.showNotification(
      "Streaming Live",
      `Loading ${src.sourceName || src.provider || "Anime"}`,
    );
  }
}

// Anime direct-stream playback (parity with mobile: AllAnime -> direct URL).
// `startPositionMs` is optional: null = use saved resume position, 0 = from start.
async function playAnimeStream(
  media,
  episode,
  season = 1,
  startPositionMs = null,
) {
  const seasonSelector = document.getElementById("season-selector");
  const selectedSeason =
    parsePositiveIntOrNull(seasonSelector && seasonSelector.value) ||
    parsePositiveIntOrNull(season) ||
    1;
  const selectedEpisode = parsePositiveIntOrNull(episode) || 1;
  captureReturnToDetailContext(media, selectedSeason, selectedEpisode);
  closeDetailModal();

  // Leaving any previous direct session: flush final progress first.
  stopActiveDirectPlayback({ saveFinal: true });

  if (state.activeEmbedSession && state.activeEmbedSession.cancel) {
    state.activeEmbedSession.cancel();
    state.activeEmbedSession = null;
  }
  if (state.activeHls) {
    try {
      state.activeHls.destroy();
    } catch (_) {}
    state.activeHls = null;
  }
  const titleEl = document.getElementById("player-stream-title");
  titleEl.textContent = `${media.title} — E${selectedEpisode}`;
  const container = document.getElementById("webview-container");
  unsizeWebview(state.activeWebview);
  state.activeWebview = null;

  // Immersive Loader (Lordflix anime loading style)
  container.innerHTML = `
    <div class="absolute inset-0 z-0 opacity-20 bg-cover bg-center" style="background-image: url('${media.backdrop || media.poster}')"></div>
    <div class="absolute inset-0 bg-gradient-to-t from-[#050505] via-[#050505]/80 to-[#050505]/40 z-10"></div>
    <div class="relative z-20 flex flex-col items-center justify-center h-full gap-4 animate-pulse">
        <img src="https://media.tenor.com/e2qU2h4aEVEAAAAC/anime-cooking.gif" class="w-32 h-32 rounded-xl border-4 border-white/10 shadow-2xl">
        <h2 class="text-white text-2xl font-black tracking-widest drop-shadow-lg">Brewing Sources...</h2>
        <p class="text-gray-400 font-semibold tracking-wide text-sm drop-shadow-md">${media.title} • Episode ${selectedEpisode}</p>
    </div>
  `;
  document.getElementById("player-overlay").classList.remove("hidden");

  try {
    const src = await window.OmniAnime.resolveSource(media, selectedEpisode, {
      dub: state.preferDub || false,
      seasonNumber: selectedSeason,
    });
    state.animeResume = { media, episode: selectedEpisode };
    if (src && src.kind === "embed") {
      playAnimeEmbed(container, media, selectedEpisode, src);
      return;
    }

    const explicitStartMs =
      Number.isFinite(Number(startPositionMs)) && Number(startPositionMs) >= 0
        ? Math.max(0, Math.round(Number(startPositionMs)))
        : null;
    const resumeMs =
      explicitStartMs !== null
        ? explicitStartMs
        : findResumePositionMs(media, selectedSeason, selectedEpisode);

    playDirectVideo(
      container,
      src.url,
      src.referer,
      media,
      selectedEpisode,
      selectedSeason,
      resumeMs,
    );
  } catch (e) {
    if (e && e.name === "CaptchaRequiredError") {
      showAnimeCaptcha(e.url, () =>
        playAnimeStream(media, selectedEpisode, selectedSeason, startPositionMs),
      );
      return;
    }
    console.warn("[Omniverse] anime resolve failed:", e);

    container.innerHTML =
      '<div style="display:flex;height:100%;align-items:center;justify-content:center;color:#fff;font-weight:600">No playable ani-cli source found.</div>';
    window.electron.showNotification(
      "Playback",
      "No playable ani-cli anime source found.",
    );
  }
}

// Plays a direct mp4/m3u8 URL in a <video> (hls.js for HLS). The stream host's
// Referer is applied to HLS segment requests; for progressive mp4 the main
// process injects it (see main.js onBeforeSendHeaders).
function playDirectVideo(
  container,
  url,
  referer,
  media = null,
  episode = null,
  seasonNumber = 1,
  startPositionMs = null,
) {
  // Register the stream host so the main process injects the Referer for it.
  try {
    window.electron.registerAnimeHost(new URL(url).host);
  } catch (_) {}

  // Replacing any existing direct session: persist its final progress first.
  stopActiveDirectPlayback({ saveFinal: true });

  if (state.activeEmbedSession && state.activeEmbedSession.cancel) {
    state.activeEmbedSession.cancel();
    state.activeEmbedSession = null;
  }
  container.innerHTML = "";
  const video = document.createElement("video");
  video.className = "webview-player";
  video.controls = true;
  video.autoplay = true;
  video.style.width = "100%";
  video.style.height = "100%";
  video.style.background = "#000";
  container.appendChild(video);
  state.activeWebview = null;

  let skipIntervals = [];
  let skippedTypes = new Set();

  video.addEventListener("loadedmetadata", async () => {
    const durationSec = Number(video.duration);

    if (
      startPositionMs != null &&
      durationSec > 0 &&
      Number.isFinite(durationSec) &&
      startPositionMs > 0
    ) {
      const resumeSec = Math.min(
        startPositionMs / 1000,
        Math.max(0, durationSec - 2),
      );
      if (Number.isFinite(resumeSec) && resumeSec > 0) {
        try {
          video.currentTime = resumeSec;
        } catch (_) {}
      }
    }

    if (media) {
      startDirectPlaybackTracking(video, media, seasonNumber, episode);
    }

    if (!media || !episode) return;

    const anilistId =
      parsePositiveIntOrNull(media.anilistId) ||
      (() => {
        const m = /anilist:anime:(\d+)/i.exec(media.id || "");
        return m ? parsePositiveIntOrNull(m[1]) : null;
      })();
    if (!anilistId) return;

    const mappedAniSkipEpisode =
      window.OmniAnime && typeof window.OmniAnime.aniSkipEpisodeFor === "function"
        ? parsePositiveIntOrNull(
            window.OmniAnime.aniSkipEpisodeFor(media, seasonNumber, episode),
          )
        : null;
    const skipEpisode = mappedAniSkipEpisode || parsePositiveIntOrNull(episode);
    if (!skipEpisode) return;

    const duration = Math.round(video.duration) || 1440;
    skipIntervals = await fetchDesktopAniSkip(anilistId, skipEpisode, duration);
  });

  video.addEventListener("timeupdate", () => {
    const current = video.currentTime;
    if (skipIntervals && skipIntervals.length > 0) {
      for (const interval of skipIntervals) {
        if (skippedTypes.has(interval.type)) continue;
        if (current >= interval.start && current < interval.end - 1) {
          skippedTypes.add(interval.type);
          video.currentTime = interval.end;
          showPlayerToast(
            "Auto Skipped",
            interval.type === "op"
              ? "Opening Intro"
              : interval.type === "recap"
                ? "Recap"
                : "Ending Outro",
          );
          break;
        }
      }
    }
  });

  video.addEventListener("ended", () => {
    stopActiveDirectPlayback({ saveFinal: true, completed: true });
  });

  const isHls = /\.m3u8(\?|$)/i.test(url);
  if (isHls && window.Hls && window.Hls.isSupported()) {
    const hls = new window.Hls({
      xhrSetup: (xhr) => {
        try {
          xhr.setRequestHeader("Referer", referer || "https://allmanga.to");
        } catch (_) {}
      },
    });
    hls.loadSource(url);
    hls.attachMedia(video);
    state.activeHls = hls;
  } else {
    video.src = url;
  }
  video.play().catch(() => {});
}

async function fetchDesktopAniSkip(anilistId, episode, durationSec) {
  return [];
}

  const parseIntervals = (raw) => {
    if (!raw) return [];
    let data;
    try {
      data = typeof raw === "string" ? JSON.parse(raw) : raw;
    } catch {
      return [];
    }
    if (!data || data.found !== true || !Array.isArray(data.results)) return [];

    const allowedTypes = new Set(["op", "ed", "recap"]);
    return data.results
      .map((entry) => {
        const type = ((entry && (entry.skipType || entry.skip_type)) || "")
          .toString()
          .toLowerCase();
        if (!allowedTypes.has(type)) return null;

        const interval = entry && entry.interval;
        const start = Number(interval && interval.startTime);
        const end = Number(interval && interval.endTime);
        if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
          return null;
        }

        return { type, start, end };
      })
      .filter(Boolean)
      .sort((a, b) => a.start - b.start);
  };

  const fetchUrl = async (url) => {
    try {
      const res = await appFetch(url, "GET", {
        Accept: "application/json",
      });
      if (!res.ok || !res.html) return [];
      return parseIntervals(res.html);
    } catch (e) {
      console.warn("AniSkip fetch failed:", e);
      return [];
    }
  };

  let list = await fetchUrl(
    `https://api.aniskip.com/v2/skip-times/${aniList}/${ep}?types[]=op&types[]=ed&types[]=recap&episodeLength=${length}`,
  );
  if (list.length) return list;

  list = await fetchUrl(
    `https://api.aniskip.com/v2/skip-times/${aniList}/${ep}?types[]=op&types[]=ed&types[]=recap&episodeLength=1440`,
  );
  if (list.length) return list;

  return fetchUrl(
    `https://api.aniskip.com/v1/skip-times/${aniList}/${ep}?types=op&types=ed`,
  );
}

function showPlayerToast(title, body) {
  const toast = document.getElementById("player-toast");
  const titleEl = document.getElementById("player-toast-title");
  const bodyEl = document.getElementById("player-toast-body");
  if (!toast || !titleEl || !bodyEl) return;

  titleEl.textContent = title;
  bodyEl.textContent = body;
  toast.classList.remove("hidden");

  if (state.toastTimeout) clearTimeout(state.toastTimeout);
  state.toastTimeout = setTimeout(() => {
    toast.classList.add("hidden");
  }, 4000);
}

// Captcha WebView: AllAnime gated the request. Let the user solve it, then retry.
// The webview shares the persist:player partition; main.js forwards that
// partition's cookies to OmniAnime's fetches so the retry is authenticated.
function showAnimeCaptcha(url, onSolved) {
  const container = document.getElementById("webview-container");
  container.innerHTML = "";
  document.getElementById("player-overlay").classList.remove("hidden");
  document.getElementById("player-stream-title").textContent =
    "Verify to continue — solve the check, then press Done";

  const webview = document.createElement("webview");
  webview.className = "webview-player";
  webview.setAttribute("partition", "persist:player");
  webview.setAttribute("src", url);
  webview.style.width = "100%";
  webview.style.height = "calc(100% - 52px)";
  container.appendChild(webview);

  const bar = document.createElement("div");
  bar.style.cssText =
    "display:flex;justify-content:flex-end;gap:8px;padding:10px;background:#000";
  const done = document.createElement("button");
  done.textContent = "Done";
  done.style.cssText =
    "background:#fff;color:#000;font-weight:700;border:none;border-radius:999px;padding:8px 22px;cursor:pointer";
  done.onclick = async () => {
    try {
      await window.electron.syncPlayerCookies();
    } catch (_) {}
    container.innerHTML = "";
    if (typeof onSolved === "function") onSolved();
  };
  bar.appendChild(done);
  container.appendChild(bar);
}

async function exitPlayer(options = {}) {
  const { restoreDetail = true } = options;

  stopActiveDirectPlayback({ saveFinal: true });

  if (state.activeEmbedSession && state.activeEmbedSession.cancel) {
    state.activeEmbedSession.cancel();
    state.activeEmbedSession = null;
  }
  // Stop the chromeless resolver's polling loops before tearing down the webview.
  if (vidsrcResolver) {
    vidsrcResolver.cancelled = true;
    vidsrcResolver = null;
  }
  if (state.activeHls) {
    try {
      state.activeHls.destroy();
    } catch (_) {}
    state.activeHls = null;
  }
  document.getElementById("player-overlay").classList.add("hidden");

  // Safely destroy player WebContents instantly to freeze sound, clear caches, and stop video streams
  unsizeWebview(state.activeWebview);
  const container = document.getElementById("webview-container");
  container.innerHTML = "";
  state.activeWebview = null;
  state.currentPlayback = null;

  if (window.electron && window.electron.playerStopped) {
    window.electron.playerStopped(); // GC and Cache flush trigger on main thread
  }

  if (!restoreDetail) {
    state.returnToDetailContext = null;
    return;
  }

  if (!state.returnToDetailContext) return;

  const restored = await restoreDetailFromPlaybackContext();
  if (restored) {
    state.returnToDetailContext = null;
  }
}

function togglePiP() {
  if (state.activeWebview) {
    const url =
      (state.activeEmbedSession &&
        state.activeEmbedSession.currentAttempt &&
        state.activeEmbedSession.currentAttempt.url) ||
      (typeof state.activeWebview.getURL === "function" &&
        state.activeWebview.getURL()) ||
      state.activeWebview.dataset.currentSrc ||
      state.activeWebview.getAttribute("src");
    const title = document.getElementById("player-stream-title").textContent;

    if (window.electron && window.electron.openPipWindow) {
      // Open floating window in Main Process
      window.electron.openPipWindow(url, title);

      // Close the internal player to prevent duplicate audio streams
      exitPlayer({ restoreDetail: false });
    } else if (url) {
      window.open(url, "_blank", "noopener,noreferrer");
    }
  }
}

// Live TV IPTV Player Center
let hlsInstance = null;

async function setupLiveTvCenter() {
  const select = document.getElementById("iptv-country-select");
  if (!select) return;

  select.innerHTML = '<option value="">Syncing regions...</option>';

  try {
    let countries = [];
    const cachedCountries = localStorage.getItem("iptv_countries");
    if (cachedCountries) {
      countries = JSON.parse(cachedCountries);
    } else {
      const res = await appFetch("https://iptv-web.app/");
      if (!res.ok)
        throw new Error(res.error || "Could not retrieve root catalog.");

      const parser = new DOMParser();
      const doc = parser.parseFromString(res.html, "text/html");
      const links = doc.querySelectorAll("a[href^='/']");

      links.forEach((link) => {
        const href = link.getAttribute("href");
        const match = href.match(/^\/([A-Z]{2})\/$/);
        if (match) {
          const code = match[1];
          const h2 = link.querySelector("h2");
          const emoji = h2 ? h2.textContent.trim() : "🏳️";
          let name = link.textContent.replace(emoji, "").trim();
          if (name) {
            countries.push({ code, emoji, name });
          }
        }
      });

      countries.sort((a, b) => a.name.localeCompare(b.name));

      if (countries.length > 0) {
        localStorage.setItem("iptv_countries", JSON.stringify(countries));
      }
    }

    state.iptvCountries = countries;

    select.innerHTML = "";
    countries.forEach((c) => {
      const option = document.createElement("option");
      option.value = c.code;
      option.textContent = `${c.emoji} ${c.name} (${c.code})`;
      if (c.code === "US") option.selected = true; // default
      select.appendChild(option);
    });

    // Start with default USA
    await loadIptvChannels("US");
  } catch (err) {
    console.error("IPTV Country fetch error: ", err);
    select.innerHTML = '<option value="">Error loading countries</option>';
    window.electron.showNotification(
      "IPTV Sync Error",
      "Could not sync regions: " + err.message,
    );
  }
}

async function onIptvCountryChanged() {
  const select = document.getElementById("iptv-country-select");
  if (!select) return;
  const code = select.value;
  if (code) {
    await loadIptvChannels(code);
  }
}

async function loadIptvChannels(countryCode) {
  const container = document.getElementById("channel-list-container");
  if (!container) return;

  container.innerHTML = `
    <div class="flex flex-col items-center justify-center py-12 gap-2 text-gray-500">
      <div class="w-6 h-6 rounded-full border-2 border-brandCyan border-t-transparent animate-spin"></div>
      <span class="text-[10px] font-bold uppercase tracking-wider text-brandCyan">Syncing Channels...</span>
    </div>
  `;

  // Clear search input
  const searchInput = document.getElementById("iptv-channel-search");
  if (searchInput) searchInput.value = "";

  try {
    const res = await appFetch(`https://iptv-web.app/${countryCode}/`);
    if (!res.ok) throw new Error(res.error || "Channel request failed");

    const parser = new DOMParser();
    const doc = parser.parseFromString(res.html, "text/html");
    const links = doc.querySelectorAll("a[href^='/']");

    const channels = [];
    links.forEach((link) => {
      const href = link.getAttribute("href");
      const segments = href.split("/").filter(Boolean);
      if (segments.length === 2 && segments[0] === countryCode) {
        const id = segments[1];
        const img = link.querySelector("img");
        const logo = img ? img.getAttribute("src") : "";
        const name = link.textContent.trim();
        if (name && id) {
          channels.push({
            id,
            name,
            logo: logo || "",
            url: href,
          });
        }
      }
    });

    state.iptvChannels = channels;
    state.filteredIptvChannels = channels;

    renderIptvChannelsList();
  } catch (err) {
    console.error("IPTV Channels fetch error: ", err);
    container.innerHTML = `
      <div class="flex flex-col items-center justify-center py-12 text-center gap-2 text-gray-500 p-4">
        <i data-lucide="alert-circle" class="w-6 h-6 text-red-500/50"></i>
        <h4 class="text-xs font-bold text-gray-400">Failed to Load Channels</h4>
        <p class="text-[10px] leading-relaxed text-gray-600">Could not sync channel listing. Try another region.</p>
      </div>
    `;
    lucide.createIcons();
  }
}

function renderIptvChannelsList() {
  const container = document.getElementById("channel-list-container");
  if (!container) return;
  container.innerHTML = "";

  if (state.filteredIptvChannels.length === 0) {
    container.innerHTML = `
      <div class="text-center py-12 text-xs text-gray-500">
        No channels matched filter.
      </div>
    `;
    return;
  }

  state.filteredIptvChannels.forEach((channel) => {
    const btn = document.createElement("button");
    btn.className =
      "w-full text-left p-2.5 rounded-lg hover:bg-white/[0.02] border border-transparent hover:border-white/[0.04] text-xs font-semibold flex items-center gap-3 transition duration-200 no-drag";
    btn.onclick = () => playLiveChannel(channel, btn);

    const logoHtml =
      channel.logo && channel.logo.startsWith("http")
        ? `<img src="${channel.logo}" class="w-7 h-7 object-contain bg-brandTert p-1 rounded-lg" loading="lazy" onerror="this.onerror=null; this.outerHTML='<span class=\"text-lg bg-brandTert p-1.5 rounded-lg\">📺</span>'">`
        : `<span class="text-lg bg-brandTert p-1.5 rounded-lg">📺</span>`;

    btn.innerHTML = `
      ${logoHtml}
      <div class="flex-1 min-w-0">
        <h4 class="text-xs font-bold text-gray-200 truncate leading-snug">${channel.name}</h4>
        <span class="text-[9px] text-gray-500 font-semibold block uppercase tracking-wider truncate">${channel.id}</span>
      </div>
    `;
    container.appendChild(btn);
  });
}

function filterIptvChannels() {
  const input = document.getElementById("iptv-channel-search");
  if (!input) return;
  const q = input.value.toLowerCase().trim();

  if (!q) {
    state.filteredIptvChannels = state.iptvChannels;
  } else {
    state.filteredIptvChannels = state.iptvChannels.filter(
      (c) => c.name.toLowerCase().includes(q) || c.id.toLowerCase().includes(q),
    );
  }
  renderIptvChannelsList();
}

async function playLiveChannel(channel, buttonEl) {
  // Highlight active channel button
  const buttons = document.querySelectorAll("#channel-list-container button");
  buttons.forEach((b) =>
    b.classList.remove("bg-brandCyan/10", "border-brandCyan/20"),
  );

  if (buttonEl) {
    buttonEl.classList.add("bg-brandCyan/10", "border-brandCyan/20");
  }

  // Remove placeholder overlay
  document.getElementById("player-placeholder").classList.add("hidden");

  // Show resolving loader
  const loader = document.getElementById("iptv-resolving-loader");
  if (loader) loader.classList.remove("hidden");

  const video = document.getElementById("livetv-player");

  // Clean up existing Hls engine
  if (hlsInstance) {
    hlsInstance.destroy();
    hlsInstance = null;
  }

  try {
    const streamUrl = await resolveIptvStream(channel.url);
    if (!streamUrl) throw new Error("No stream URL found in meta headers.");

    // Hide resolving loader
    if (loader) loader.classList.add("hidden");

    // Play .m3u8 native HLS streams
    if (Hls.isSupported()) {
      hlsInstance = new Hls({
        enableWorker: true,
        lowLatencyMode: true,
      });
      hlsInstance.loadSource(streamUrl);
      hlsInstance.attachMedia(video);
      hlsInstance.on(Hls.Events.MANIFEST_PARSED, () => {
        video.play().catch((err) => console.log("Autoplay blocked: ", err));
      });
      hlsInstance.on(Hls.Events.ERROR, (event, data) => {
        if (data.fatal) {
          switch (data.type) {
            case Hls.ErrorTypes.NETWORK_ERROR:
              hlsInstance.startLoad();
              break;
            case Hls.ErrorTypes.MEDIA_ERROR:
              hlsInstance.recoverMediaError();
              break;
            default:
              console.error("LiveTV Fatal Error: ", data);
              break;
          }
        }
      });
    } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
      // Safari / Native support fallback
      video.src = streamUrl;
      video.addEventListener("loadedmetadata", () => {
        video.play();
      });
    }

    window.electron.showNotification(
      "Live TV Center",
      `Now streaming: ${channel.name}`,
    );
  } catch (err) {
    console.error("IPTV Stream resolution failed: ", err);
    if (loader) loader.classList.add("hidden");

    const placeholder = document.getElementById("player-placeholder");
    placeholder.classList.remove("hidden");
    placeholder.querySelector("p").textContent =
      `Playback failed: Could not resolve stream URL for ${channel.name}. The stream may be offline.`;

    window.electron.showNotification(
      "Stream Offline",
      `Could not resolve video stream for ${channel.name}`,
    );
  }
}

async function resolveIptvStream(channelUrl) {
  const fullUrl = `https://iptv-web.app${channelUrl}`;
  const res = await appFetch(fullUrl);
  if (!res.ok) throw new Error(res.error || "Channel request failed");

  // Extract using meta tag regex (og:video)
  const m3u8Regex = /content="([^"]+\.m3u8[^"]*)"/i;
  const match = m3u8Regex.exec(res.html);
  if (match && match[1]) {
    return match[1].trim();
  }

  // Fallback: search for any m3u8 URL in quotes inside the HTML page
  const generalM3u8Regex = /"([^"]+\.m3u8[^"]*)"/i;
  const generalMatch = generalM3u8Regex.exec(res.html);
  if (generalMatch && generalMatch[1]) {
    return generalMatch[1].trim();
  }

  return null;
}

// Global Search Filtering Handler
function setupSearchInput() {
  const input = document.getElementById("search-input");
  let searchTimeout = null;

  input.addEventListener("input", (e) => {
    const val = e.target.value.toLowerCase().trim();
    if (searchTimeout) clearTimeout(searchTimeout);

    if (!val) {
      document.getElementById("grid-search-results").innerHTML = "";
      return;
    }

    searchTimeout = setTimeout(async () => {
      if (!state.tmdbToken) {
        showGridMessage(
          "grid-search-results",
          "Connect TMDB to search movies and TV",
          "Search now uses live TMDB results only. Add your key in Settings to query the latest catalogue.",
          "key-round",
        );
        return;
      }

      showGridLoading("grid-search-results", "Searching TMDB…");
      const searchData = await fetchTmdb("search/multi", { query: val });
      const items = ((searchData && searchData.results) || [])
        .filter(
          (item) =>
            (item.media_type === "movie" || item.media_type === "tv") &&
            (item.poster_path || item.backdrop_path),
        )
        .map((item) => mapTmdbItem(item, item.media_type));

      if (items.length) {
        renderGrid("grid-search-results", items.slice(0, 24), true);
      } else {
        showGridMessage(
          "grid-search-results",
          "No live matches",
          `TMDB returned no image-backed movie or TV matches for “${val}”.`,
          "search-x",
        );
      }
      if (window.lucide) lucide.createIcons();
    }, 400);
  });
}

// Clear cached network data and pull a fresh catalogue (homepage rails, grids).
async function refreshCatalog(btn) {
  const original = btn ? btn.innerHTML : null;
  if (btn) {
    btn.disabled = true;
    btn.innerHTML = `<i data-lucide="refresh-cw" class="w-4 h-4 animate-spin"></i> Refreshing…`;
    if (window.lucide) lucide.createIcons();
  }
  try {
    if (window.electron && window.electron.clearCache) {
      await window.electron.clearCache();
    }
    state.animeCatalog = [];
    await renderCatalogFeeds();
    switchScreen("home");
    if (window.electron) {
      window.electron.showNotification(
        "Fresh Pull",
        "Cache cleared and the latest catalogue has been reloaded.",
      );
    }
  } catch (e) {
    if (window.electron) {
      window.electron.showNotification(
        "Refresh Failed",
        String((e && e.message) || e),
      );
    }
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.innerHTML = original;
      if (window.lucide) lucide.createIcons();
    }
  }
}

// Adblock Stats syncing
function setupAdblockObserver() {
  window.electron.onAdBlocked((count) => {
    state.adBlockCount = count;
    document.getElementById("adblock-counter").textContent = count;
    document.getElementById("dashboard-ads-blocked").textContent = count;
  });
}

// Save options inside settings
function savePlaybackSettings() {
  const select = document.getElementById("vidsrc-domain-select");
  state.vidsrcDomain = select.value;
  localStorage.setItem("omni_vidsrc_domain", select.value);
  if (window.electron && window.electron.showNotification) {
    window.electron.showNotification(
      "Preferences Updated",
      `Preferred embed provider changed to: ${select.value}`,
    );
  }
}

// Save TMDB key
function saveTmdbToken() {
  const input = document.getElementById("tmdb-token-input");
  state.tmdbToken = input.value.trim();
  localStorage.setItem("omni_tmdb_token", state.tmdbToken);

  if (state.tmdbToken) {
    window.electron.showNotification(
      "Token Saved",
      "TMDB Read Access Token applied. Verifying sync channels...",
    );
    // Future expansion: call the TMDB api directly to fetch real-time trending collections
  } else {
    window.electron.showNotification(
      "Token Purged",
      "Read Access Token cleared. Movie and TV rails will stay empty until TMDB is reconnected.",
    );
  }
  // Reload feeds on TMDB token change
  renderCatalogFeeds();
  hydrateProviderRailLogos();
}

// Save All Advanced API Keys
function saveAllApiKeys() {
  const oldClientId = state.traktClientId;
  const oldClientSecret = state.traktClientSecret;

  state.traktToken = document.getElementById("trakt-token-input").value.trim();
  state.traktClientId = document
    .getElementById("trakt-client-id-input")
    .value.trim();
  state.traktClientSecret = document
    .getElementById("trakt-client-secret-input")
    .value.trim();
  state.pixeldrainApiKey = document
    .getElementById("pixeldrain-key-input")
    .value.trim();
  state.tvdbApiKey = document.getElementById("tvdb-key-input").value.trim();
  state.tvdbPin = document.getElementById("tvdb-pin-input").value.trim();
  state.anilistAccessToken = document
    .getElementById("anilist-token-input")
    .value.trim();

  if (
    state.traktClientId !== oldClientId ||
    state.traktClientSecret !== oldClientSecret
  ) {
    state.traktRefreshToken = "";
    state.traktTokenExpiresAt = 0;
    state.traktUsername = "";
    localStorage.removeItem("omni_trakt_refresh_token");
    localStorage.removeItem("omni_trakt_expires_at");
    localStorage.removeItem("omni_trakt_username");
  }

  localStorage.setItem("omni_trakt_token", state.traktToken);
  localStorage.setItem("omni_trakt_client_id", state.traktClientId);
  localStorage.setItem("omni_trakt_client_secret", state.traktClientSecret);
  localStorage.setItem("omni_pixeldrain_key", state.pixeldrainApiKey);
  localStorage.setItem("omni_tvdb_key", state.tvdbApiKey);
  localStorage.setItem("omni_tvdb_pin", state.tvdbPin);
  localStorage.setItem("omni_anilist_token", state.anilistAccessToken);

  window.electron.showNotification(
    "Credentials Saved",
    "All updated API keys and system credentials have been safely stored locally.",
  );

  // Sync back to Trakt if connected
  if (state.traktToken) {
    pushToTrakt();
  }
}

// Decode Base64 Sync codes generated by iOS / Android (Zero-Config Cloud Sync)
function importSyncCode() {
  const input = document.getElementById("sync-code-input");
  const rawCode = input.value.trim();

  if (!rawCode.startsWith("OMNIVERSE-SYNC1:")) {
    window.electron.showNotification(
      "Sync Failed",
      "Invalid Sync QR payload. Ensure standard prefix is correct.",
    );
    return;
  }

  try {
    const base64Data = rawCode.replace("OMNIVERSE-SYNC1:", "");
    const decodedString = atob(base64Data);
    const config = JSON.parse(decodedString);

    if (config.tmdb_token) {
      state.tmdbToken = config.tmdb_token;
      localStorage.setItem("omni_tmdb_token", config.tmdb_token);
    }

    if (config.settings && config.settings.vidsrcDomain) {
      state.vidsrcDomain = config.settings.vidsrcDomain;
      localStorage.setItem("omni_vidsrc_domain", config.settings.vidsrcDomain);
    }

    // Parse Trakt Sync credentials
    if (config.trakt_access_token) {
      state.traktToken = config.trakt_access_token;
      localStorage.setItem("omni_trakt_token", config.trakt_access_token);
    }
    if (config.trakt_refresh_token) {
      state.traktRefreshToken = config.trakt_refresh_token;
      localStorage.setItem(
        "omni_trakt_refresh_token",
        config.trakt_refresh_token,
      );
    }
    if (config.trakt_token_expires_at) {
      state.traktTokenExpiresAt = parseInt(config.trakt_token_expires_at) || 0;
      localStorage.setItem("omni_trakt_expires_at", state.traktTokenExpiresAt);
    }
    if (config.trakt_username) {
      state.traktUsername = config.trakt_username;
      localStorage.setItem("omni_trakt_username", config.trakt_username);
    }
    if (config.trakt_client_id) {
      state.traktClientId = config.trakt_client_id;
      localStorage.setItem("omni_trakt_client_id", config.trakt_client_id);
    }
    if (config.trakt_client_secret) {
      state.traktClientSecret = config.trakt_client_secret;
      localStorage.setItem(
        "omni_trakt_client_secret",
        config.trakt_client_secret,
      );
    }
    if (config.pixeldrain_api_key) {
      state.pixeldrainApiKey = config.pixeldrain_api_key;
      localStorage.setItem("omni_pixeldrain_key", config.pixeldrain_api_key);
    }

    // Parse TVDB & AniList credentials
    if (config.tvdb_api_key) {
      state.tvdbApiKey = config.tvdb_api_key;
      localStorage.setItem("omni_tvdb_key", config.tvdb_api_key);
    }
    if (config.tvdb_pin) {
      state.tvdbPin = config.tvdb_pin;
      localStorage.setItem("omni_tvdb_pin", config.tvdb_pin);
    }
    if (config.anilist_access_token) {
      state.anilistAccessToken = config.anilist_access_token;
      localStorage.setItem("omni_anilist_token", config.anilist_access_token);
    }

    // Update all inputs on screen
    loadSavedPreferences();

    input.value = "";
    window.electron.showNotification(
      "Sync Successful",
      "Cloud Sync finished. Re-loaded credentials, accounts, and play preferences.",
    );

    // Refresh feed configurations and pull history
    renderCatalogFeeds();
    hydrateProviderRailLogos();

    if (state.traktToken) {
      pullFromTrakt();
    }
  } catch (err) {
    console.error("Sync parsing error: ", err);
    window.electron.showNotification(
      "Sync Error",
      "Could not parse credentials. Package base64 corrupted.",
    );
  }
}

const TOKEN_REFRESH_SKEW_MS = 5 * 60 * 1000;

async function ensureFreshTraktToken() {
  if (!state.traktToken || !state.traktTokenExpiresAt) return;

  const now = Date.now();
  const refreshAt = now + TOKEN_REFRESH_SKEW_MS;

  // If token is still fresh, do nothing
  if (state.traktTokenExpiresAt > refreshAt) return;

  if (!state.traktRefreshToken || !state.traktClientSecret) {
    console.warn(
      "Trakt token expired but cannot refresh (missing refresh token or client secret).",
    );
    return;
  }

  console.log("Trakt token is expired or close to expiring, refreshing...");

  try {
    const url = "https://api.trakt.tv/oauth/token";
    const body = {
      refresh_token: state.traktRefreshToken.trim(),
      client_id: state.traktClientId.trim(),
      client_secret: state.traktClientSecret.trim(),
      redirect_uri: "omniplay://trakt/oauth",
      grant_type: "refresh_token",
    };
    const headers = {
      "Content-Type": "application/json",
    };

    const res = await appFetch(url, "POST", headers, body);
    if (!res.ok) {
      throw new Error(
        `Trakt token refresh failed with status ${res.status}: ${res.error || ""}`,
      );
    }

    const data = JSON.parse(res.html);
    const createdAtSeconds = data.created_at || Math.floor(Date.now() / 1000);
    const expiresIn = data.expires_in || 0;
    const expiresAt =
      expiresIn <= 0 ? 0 : (createdAtSeconds + expiresIn) * 1000;

    state.traktToken = data.access_token || "";
    state.traktRefreshToken = data.refresh_token || "";
    state.traktTokenExpiresAt = expiresAt;

    localStorage.setItem("omni_trakt_token", state.traktToken);
    localStorage.setItem("omni_trakt_refresh_token", state.traktRefreshToken);
    localStorage.setItem("omni_trakt_expires_at", expiresAt);

    loadSavedPreferences();
    console.log("Trakt token refreshed successfully.");
  } catch (err) {
    console.error("Failed to refresh Trakt access token:", err);
  }
}

// Interactively refresh and verify Trakt authentication state
async function refreshTraktLoginState() {
  const btn = document.getElementById("btn-refresh-login");
  if (btn) {
    btn.disabled = true;
    btn.innerHTML = `<i data-lucide="refresh-cw" class="w-3.5 h-3.5 inline mr-1 animate-spin"></i> Verifying...`;
    lucide.createIcons();
  }

  // Attempt to refresh the token if we have a refresh token
  await ensureFreshTraktToken();

  const token = (
    document.getElementById("trakt-token-input").value ||
    state.traktToken ||
    ""
  ).trim();
  const clientId = (
    document.getElementById("trakt-client-id-input").value ||
    state.traktClientId ||
    ""
  ).trim();

  if (!token || !clientId) {
    window.electron.showNotification(
      "Login Status",
      "Please enter your Trakt Account Token and Client ID first to verify authentication.",
    );
    if (btn) {
      btn.disabled = false;
      btn.innerHTML = `<i data-lucide="refresh-cw" class="w-3.5 h-3.5 inline mr-1 select-none"></i> Refresh Login`;
      lucide.createIcons();
    }
    return;
  }

  try {
    const url = "https://api.trakt.tv/users/settings";
    const headers = {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      "trakt-api-version": "2",
      "trakt-api-key": clientId,
    };

    const res = await appFetch(url, "GET", headers);
    if (res.ok && res.html) {
      const data = JSON.parse(res.html);
      const username =
        data.user && data.user.username ? data.user.username : "";

      // Persist verified state
      state.traktToken = token;
      state.traktClientId = clientId;
      state.traktUsername = username;
      localStorage.setItem("omni_trakt_token", token);
      localStorage.setItem("omni_trakt_client_id", clientId);
      localStorage.setItem("omni_trakt_username", username);
      loadSavedPreferences();

      window.electron.showNotification(
        "Sync Authenticated",
        username
          ? `Welcome back, ${username}! Sync channels are active.`
          : "Trakt session verified successfully.",
      );
    } else {
      window.electron.showNotification(
        "Authentication Refused",
        "Trakt rejected this Token. Please verify credentials.",
      );
    }
  } catch (err) {
    console.error("Trakt refresh settings error:", err);
    window.electron.showNotification(
      "Sync Network Warning",
      "Could not complete verification. Server connection timed out.",
    );
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.innerHTML = `<i data-lucide="refresh-cw" class="w-3.5 h-3.5 inline mr-1 select-none"></i> Refresh Login`;
      lucide.createIcons();
    }
  }
}

// ==============================================================================
// In-App Update Engine (Over-The-Air Sideloading)
// ==============================================================================
// Fallback only. The real installed version comes from app.getVersion()
// (package.json, stamped at release time) via window.electron.getAppVersion().
let APP_VERSION = "2.1.0";
let activeUpdateAssetUrl = "";

function isNewerVersion(current, remote) {
  const currClean = current.trim().replace(/^v/i, "");
  const remoClean = remote.trim().replace(/^v/i, "");
  if (currClean === remoClean) return false;

  const currParts = currClean.split(".").map((x) => parseInt(x, 10) || 0);
  const remoParts = remoClean.split(".").map((x) => parseInt(x, 10) || 0);
  const size = Math.max(currParts.length, remoParts.length);

  for (let i = 0; i < size; i++) {
    const cVal = currParts[i] || 0;
    const rVal = remoParts[i] || 0;
    if (rVal > cVal) return true;
    if (rVal < cVal) return false;
  }
  return false;
}

async function checkAppUpdates(silent = false) {
  const checkBtn = document.getElementById("check-update-btn");
  if (checkBtn && !silent) {
    checkBtn.disabled = true;
    checkBtn.textContent = "Checking...";
  }

  try {
    // Resolve the true installed version (stamped into package.json at release).
    try {
      if (window.electron.getAppVersion) {
        APP_VERSION = (await window.electron.getAppVersion()) || APP_VERSION;
      }
    } catch (_) {}

    const res = await appFetch(
      "https://api.github.com/repos/FiNiX-GaMmA/omniverse/releases/latest",
    );
    if (!res.ok) throw new Error(res.error || "GitHub request failed");

    const release = JSON.parse(res.html);
    const remoteVersion = release.tag_name || "";
    const releaseNotes = release.body || "No release notes available.";

    // Only prompt when the latest release is strictly newer than what's installed.
    if (isNewerVersion(APP_VERSION, remoteVersion)) {
      const platform = await window.electron.getPlatform();
      let arch = "x64";
      try {
        if (window.electron.getArch) {
          arch = (await window.electron.getArch()) || "x64";
        }
      } catch (_) {}
      let targetAsset = null;

      // Filter assets based on host platform extension and CPU architecture
      if (release.assets && Array.isArray(release.assets)) {
        // Try to find an exact match for architecture first
        release.assets.forEach((asset) => {
          const name = asset.name.toLowerCase();
          if (
            platform === "win32" &&
            name.endsWith(".exe") &&
            !name.includes("unsigned") &&
            !name.includes("apk")
          ) {
            if (
              name.includes(arch) ||
              (arch === "x64" &&
                !name.includes("arm64") &&
                !name.includes("arm32"))
            ) {
              targetAsset = asset;
            }
          } else if (platform === "darwin" && name.endsWith(".dmg")) {
            if (
              name.includes(arch) ||
              (arch === "arm64" && name.includes("arm")) ||
              (arch === "x64" &&
                (name.includes("x64") ||
                  name.includes("intel") ||
                  name.includes("universal")))
            ) {
              targetAsset = asset;
            }
          } else if (
            platform === "linux" &&
            (name.endsWith(".appimage") || name.endsWith(".deb"))
          ) {
            if (
              name.includes(arch) ||
              (arch === "x64" &&
                (name.includes("amd64") || name.includes("x86_64")))
            ) {
              if (!targetAsset || name.endsWith(".appimage")) {
                targetAsset = asset;
              }
            }
          }
        });
        // Fallback to first matching platform asset if no architecture-specific asset matches
        if (!targetAsset) {
          release.assets.forEach((asset) => {
            const name = asset.name.toLowerCase();
            if (
              platform === "win32" &&
              name.endsWith(".exe") &&
              !name.includes("unsigned") &&
              !name.includes("apk")
            ) {
              if (!targetAsset) targetAsset = asset;
            } else if (platform === "darwin" && name.endsWith(".dmg")) {
              if (!targetAsset) targetAsset = asset;
            } else if (
              platform === "linux" &&
              (name.endsWith(".appimage") || name.endsWith(".deb"))
            ) {
              if (!targetAsset || name.endsWith(".appimage")) {
                targetAsset = asset;
              }
            }
          });
        }
      }

      if (targetAsset) {
        activeUpdateAssetUrl = targetAsset.browser_download_url;

        // Display update dialog
        document.getElementById("new-version-title").textContent =
          `Version ${remoteVersion}`;
        document.getElementById("new-version-notes").textContent = releaseNotes;

        document.getElementById("update-status-box").classList.add("hidden");
        document
          .getElementById("update-found-panel")
          .classList.remove("hidden");

        window.electron.showNotification(
          "Omniverse Update Available",
          `Version ${remoteVersion} has been released! Open Settings to download and install.`,
        );
      } else {
        if (!silent) {
          window.electron.showNotification(
            "Update Available",
            `Omniverse v${remoteVersion} is released, but the installer for ${platform} is compiling.`,
          );
        }
      }
    } else {
      if (!silent) {
        window.electron.showNotification(
          "Up To Date",
          "You are running the latest version of Omniverse Desktop.",
        );
      }
    }
  } catch (err) {
    console.error("Update Checker error: ", err);
    if (!silent) {
      window.electron.showNotification(
        "Update Check Failed",
        "Could not check for newer releases.",
      );
    }
  } finally {
    if (checkBtn && !silent) {
      checkBtn.disabled = false;
      checkBtn.textContent = "Check Update";
    }
  }
}

async function startOtaUpdate() {
  if (!activeUpdateAssetUrl) return;

  const startBtn = document.getElementById("start-update-btn");
  if (startBtn) startBtn.classList.add("hidden");

  const progressContainer = document.getElementById(
    "update-progress-container",
  );
  if (progressContainer) progressContainer.classList.remove("hidden");

  const pctLabel = document.getElementById("update-progress-pct");
  const progressBar = document.getElementById("update-progress-bar");

  // Listen for progress callbacks from Node.js process
  const unsubscribe = window.electron.onUpdateProgress((pct) => {
    if (pctLabel) pctLabel.textContent = `${pct}%`;
    if (progressBar) progressBar.style.width = `${pct}%`;
  });

  try {
    const res = await window.electron.downloadUpdate(activeUpdateAssetUrl);
    if (!res.ok) throw new Error(res.error || "File download failed");

    // Success: installer launched and app is quitting
  } catch (err) {
    console.error("OTA update error: ", err);
    unsubscribe();
    if (progressContainer) progressContainer.classList.add("hidden");
    if (startBtn) startBtn.classList.remove("hidden");

    window.electron.showNotification(
      "OTA Update Failed",
      "Could not download the update package: " + err.message,
    );
  }
}

// ==============================================================================
// Cross-Device Dynamic Pairing Handshake (Inverted Sync)
// ==============================================================================
let activePairingKey = "";

async function encryptAES(text, keyString) {
  const enc = new TextEncoder();
  const keyData = enc.encode(keyString);
  const cryptoKey = await window.crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "AES-CBC" },
    false,
    ["encrypt"],
  );
  const iv = keyData; // Use key as IV for single-use pairing
  const ciphertext = await window.crypto.subtle.encrypt(
    { name: "AES-CBC", iv: iv },
    cryptoKey,
    enc.encode(text),
  );
  return btoa(String.fromCharCode(...new Uint8Array(ciphertext)));
}

async function decryptAES(b64Cipher, keyString) {
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  const keyData = enc.encode(keyString);
  const cryptoKey = await window.crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "AES-CBC" },
    false,
    ["decrypt"],
  );
  const iv = keyData;
  const cipherData = new Uint8Array(
    atob(b64Cipher)
      .split("")
      .map((c) => c.charCodeAt(0)),
  );
  const decrypted = await window.crypto.subtle.decrypt(
    { name: "AES-CBC", iv: iv },
    cryptoKey,
    cipherData,
  );
  return dec.decode(decrypted);
}

// Renders the pairing QR locally (offline) into the given <img> element via the
// bundled qrcode.min.js. Falls back to an online generator only if the local
// library is unavailable, so pairing works on every desktop client without a
// network dependency.
function renderPairingQr(qrImg, dataStr) {
  try {
    if (typeof QRCode !== "undefined") {
      const holder = document.createElement("div");
      // eslint-disable-next-line no-new
      new QRCode(holder, {
        text: dataStr,
        width: 250,
        height: 250,
        colorDark: "#0a0b0d",
        colorLight: "#ffffff",
        correctLevel: QRCode.CorrectLevel.M,
      });
      const canvas = holder.querySelector("canvas");
      if (canvas) {
        qrImg.src = canvas.toDataURL("image/png");
        return;
      }
      const innerImg = holder.querySelector("img");
      if (innerImg && innerImg.src) {
        qrImg.src = innerImg.src;
        return;
      }
    }
  } catch (e) {
    console.warn("[Omniverse] local QR generation failed:", e);
  }
  // Fallback: online generator (only if the local library didn't produce output).
  qrImg.src =
    "https://api.qrserver.com/v1/create-qr-code/?size=250x250&color=0a0b0d&data=" +
    encodeURIComponent(dataStr);
}

async function showPairingQr() {
  const qrImg = document.getElementById("pairing-qr-img");
  const panel = document.getElementById("pairing-qr-panel");
  const pairBtn = document.getElementById("show-pair-qr-btn");

  if (panel) panel.classList.remove("hidden");
  if (pairBtn) pairBtn.disabled = true;

  try {
    // Generate a random unique pairing ID (secure 16-character topic)
    const pairId =
      "omni_pair_" +
      Math.random().toString(36).substring(2, 10) +
      Math.random().toString(36).substring(2, 10);

    // Generate a cryptographically secure 16-character AES key locally (never shared online!)
    const secretKey =
      Math.random().toString(36).substring(2, 10) +
      Math.random().toString(36).substring(2, 10);
    activePairingKey = secretKey;

    // QR contains pairing ID + local encryption key
    const dataStr = "OMNIVERSE-PAIR1:" + pairId + ":" + secretKey;

    if (qrImg) renderPairingQr(qrImg, dataStr);

    // Poll the ntfy.sh topic for remote POST updates every 2 seconds
    state.pairingInterval = setInterval(async () => {
      try {
        const res = await appFetch(
          `https://ntfy.sh/${pairId}/json?poll=1`,
          "GET",
        );
        if (res.ok && res.html && res.html.trim().length > 0) {
          // Parse NDJSON lines from ntfy response
          const lines = res.html.split("\n").filter((l) => l.trim().length > 0);
          for (const line of lines) {
            const obj = JSON.parse(line);
            if (
              obj.event === "message" &&
              obj.message &&
              obj.message.trim() !== "WAITING"
            ) {
              const encryptedPayload = obj.message.trim();

              // Clear polling timer instantly on handshake success
              clearInterval(state.pairingInterval);
              state.pairingInterval = null;

              // Decrypt the payload locally using our secure local key
              const syncPayload = await decryptAES(
                encryptedPayload,
                activePairingKey,
              );

              // Auto-fill input and run decryption
              const input = document.getElementById("sync-code-input");
              if (input) input.value = syncPayload;
              importSyncCode();

              // Hide overlay panel
              if (panel) panel.classList.add("hidden");
              if (pairBtn) pairBtn.disabled = false;

              window.electron.showNotification(
                "Login Successful",
                "Paired successfully. All keys and settings restored.",
              );
              break;
            }
          }
        }
      } catch (err) {
        console.log("Pairing poll ticking...", err);
      }
    }, 2000);
  } catch (err) {
    console.error("Pairing initialization failed: ", err);
    window.electron.showNotification(
      "Pairing Error",
      "Could not initialize pairing session: " + err.message,
    );
    if (panel) panel.classList.add("hidden");
    if (pairBtn) pairBtn.disabled = false;
  }
}

function cancelPairing() {
  if (state.pairingInterval) {
    clearInterval(state.pairingInterval);
    state.pairingInterval = null;
  }
  document.getElementById("pairing-qr-panel").classList.add("hidden");
  const pairBtn = document.getElementById("show-pair-qr-btn");
  if (pairBtn) pairBtn.disabled = false;
}







// ==============================================================================
// Trakt Bidirectional Sync Engine & Continue Watching Shelf
// ==============================================================================
function normalizeWatchProgress(rawItem) {
  const source = rawItem || {};
  const poster = source.posterPath
    ? source.posterPath.startsWith("http")
      ? source.posterPath
      : `https://image.tmdb.org/t/p/w500${source.posterPath}`
    : source.poster ||
      "https://ui-avatars.com/api/?background=111&color=fff&name=Media";

  const backdrop = source.backdropPath
    ? source.backdropPath.startsWith("http")
      ? source.backdropPath
      : `https://image.tmdb.org/t/p/original${source.backdropPath}`
    : source.backdrop ||
      "https://ui-avatars.com/api/?background=111&color=fff&name=Media";

  let progress = 0;
  if (source.positionMs && source.durationMs && source.durationMs > 0) {
    progress = source.positionMs / source.durationMs;
  } else if (source.progress !== undefined) {
    progress = source.progress;
  }

  const season = parsePositiveIntOrNull(
    source.seasonNumber !== undefined ? source.seasonNumber : source.season,
  );
  const episode = parsePositiveIntOrNull(
    source.episodeNumber !== undefined ? source.episodeNumber : source.episode,
  );

  return {
    ...source,
    type: normalizeWatchType(source.type) || "movie",
    poster,
    backdrop,
    progress,
    season: season || 1,
    episode: episode || 1,
    seasonNumber: season,
    episodeNumber: episode,
  };
}

function mediaItemForWatchProgress(rawItem) {
  const entry = normalizeWatchProgress(rawItem);
  const mediaType = normalizeWatchType(entry.type) || "movie";

  const mediaItem = {
    id: entry.itemId,
    title: entry.title,
    type: mediaType,
    poster: entry.poster,
    backdrop: entry.backdrop,
    year: new Date(entry.lastWatchedAt).getFullYear(),
    rating: "—",
    overview: entry.episodeTitle
      ? `Resume watching: ${entry.episodeTitle}`
      : "Continue watching from history.",
    seasons: entry.season ? entry.season : 1,
    tmdbId: null,
    traktId: null,
    anilistId: null,
  };

  const parts = (entry.itemId || "").split(":");
  if (parts.length >= 3) {
    const provider = (parts[0] || "").toLowerCase();
    const parsedId = parsePositiveIntOrNull(parts[2]);
    if (provider === "tmdb") mediaItem.tmdbId = parsedId;
    if (provider === "trakt") mediaItem.traktId = parsedId;
    if (provider === "anilist") mediaItem.anilistId = parsedId;
  }

  return { entry, mediaItem };
}

async function focusContinueEpisodeInDetail(entry) {
  const season = parsePositiveIntOrNull(entry.seasonNumber || entry.season);
  const episode = parsePositiveIntOrNull(entry.episodeNumber || entry.episode);
  if (!season || !episode) return;

  const seasonSelector = document.getElementById("season-selector");
  if (seasonSelector) {
    const desired = String(season);
    const hasDesiredSeason = Array.from(seasonSelector.options || []).some(
      (opt) => opt.value === desired,
    );
    if (hasDesiredSeason && seasonSelector.value !== desired) {
      seasonSelector.value = desired;
      await loadSeasonEpisodes();
    }
  }

  const activeSeason =
    parsePositiveIntOrNull(
      seasonSelector && seasonSelector.value ? seasonSelector.value : season,
    ) || season;
  focusEpisodeCardInDetail(activeSeason, episode);
}

async function openContinueWatchingDetails(rawItem) {
  const { entry, mediaItem } = mediaItemForWatchProgress(rawItem);
  await openDetailModal(mediaItem);
  await focusContinueEpisodeInDetail(entry);
}

async function resolveAndPlayContinueWatching(rawItem, fromBeginning = false) {
  const { entry, mediaItem } = mediaItemForWatchProgress(rawItem);
  const season = parsePositiveIntOrNull(entry.seasonNumber || entry.season);
  const episode = parsePositiveIntOrNull(entry.episodeNumber || entry.episode);
  const savedPositionMs = Math.max(0, Math.round(Number(entry.positionMs) || 0));

  try {
    if (isLikelyAnime(mediaItem) && window.OmniAnime) {
      const explicitStartMs = fromBeginning
        ? 0
        : savedPositionMs > 0
          ? savedPositionMs
          : null;
      await playAnimeStream(
        mediaItem,
        episode || 1,
        season || 1,
        explicitStartMs,
      );
      return true;
    }

    await playStream(mediaItem, season || null, episode || null);
    return true;
  } catch (err) {
    console.warn("[Omniverse] continue watching resolve failed:", err);
    await openDetailModal(mediaItem);
    await focusContinueEpisodeInDetail(entry);
    return false;
  }
}

function closeContinueWatchingSheet() {
  const modal = document.getElementById("continue-watching-sheet");
  if (!modal) return;

  if (typeof modal.__onKeyDown === "function") {
    window.removeEventListener("keydown", modal.__onKeyDown);
  }
  modal.remove();
}

function showContinueWatchingSheet(rawItem) {
  const { entry } = mediaItemForWatchProgress(rawItem);
  closeContinueWatchingSheet();

  const title = escapeHtml(entry.title || "Untitled");
  const backdrop = entry.backdrop || entry.poster;
  const progressPercent = Math.max(0, Math.min(100, Math.round((entry.progress || 0) * 100)));
  const subtitle =
    entry.type === "tv" || entry.type === "anime"
      ? `S${entry.season || 1} E${entry.episode || 1} • ${progressPercent}% watched`
      : `${progressPercent}% watched`;

  const modal = document.createElement("div");
  modal.id = "continue-watching-sheet";
  modal.className =
    "fixed inset-0 z-[10000] detail-modal-overlay flex items-end justify-center p-4 md:p-6";
  modal.innerHTML = `
    <div class="detail-modal-card w-full max-w-md rounded-2xl border border-white/[0.08] bg-brandSec p-5 space-y-4 animate-fade-in" data-sheet-card>
      <div class="flex items-center gap-3">
        <img src="${backdrop}" alt="${title}" class="w-32 h-[72px] rounded-lg object-cover border border-white/10" onerror="this.onerror=null; this.src='https://ui-avatars.com/api/?background=111&color=fff&name=Media';">
        <div class="min-w-0 flex-1">
          <p class="text-white text-base font-black truncate">${title}</p>
          <p class="text-xs text-gray-400 font-semibold mt-0.5">${subtitle}</p>
        </div>
      </div>

      <div class="space-y-2" data-sheet-actions>
        <button data-action="resume" class="w-full rounded-xl bg-white text-black font-black py-3 text-sm hover:opacity-95 transition">▶ Resume</button>
        <button data-action="restart" class="w-full rounded-xl bg-white/10 text-white border border-white/15 font-bold py-3 text-sm hover:bg-white/15 transition">↺ Play from beginning</button>
        <button data-action="details" class="w-full rounded-xl bg-transparent text-gray-300 border border-white/10 font-semibold py-3 text-sm hover:bg-white/5 transition">ℹ Details</button>
      </div>

      <div class="hidden items-center justify-center gap-2 py-3" data-sheet-resolving>
        <div class="w-4 h-4 rounded-full border-2 border-brandCyan border-t-transparent animate-spin"></div>
        <span class="text-sm text-white font-semibold">Resolving…</span>
      </div>
    </div>
  `;

  const card = modal.querySelector("[data-sheet-card]");
  const actions = modal.querySelector("[data-sheet-actions]");
  const resolving = modal.querySelector("[data-sheet-resolving]");

  const setResolving = (value) => {
    if (!actions || !resolving) return;
    actions.classList.toggle("hidden", value);
    resolving.classList.toggle("hidden", !value);
    resolving.classList.toggle("flex", value);

    modal.querySelectorAll("button[data-action]").forEach((btn) => {
      btn.disabled = value;
    });
  };

  const runResolve = async (fromBeginning) => {
    setResolving(true);
    await resolveAndPlayContinueWatching(entry, fromBeginning);
    closeContinueWatchingSheet();
  };

  const runDetails = async () => {
    closeContinueWatchingSheet();
    await openContinueWatchingDetails(entry);
  };

  modal.addEventListener("click", () => closeContinueWatchingSheet());
  if (card) card.addEventListener("click", (event) => event.stopPropagation());

  const onKeyDown = (event) => {
    if (event.key === "Escape") {
      event.preventDefault();
      closeContinueWatchingSheet();
    }
  };
  modal.__onKeyDown = onKeyDown;
  window.addEventListener("keydown", onKeyDown);

  const resumeBtn = modal.querySelector('button[data-action="resume"]');
  const restartBtn = modal.querySelector('button[data-action="restart"]');
  const detailsBtn = modal.querySelector('button[data-action="details"]');

  if (resumeBtn) {
    resumeBtn.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      void runResolve(false);
    });
  }
  if (restartBtn) {
    restartBtn.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      void runResolve(true);
    });
  }
  if (detailsBtn) {
    detailsBtn.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      void runDetails();
    });
  }

  document.body.appendChild(modal);
}

function renderContinueWatching() {
  const container = document.getElementById("grid-continue-watching");
  const section = document.getElementById("continue-watching-section");
  if (!container || !section) return;

  if (state.watchHistory.length === 0) {
    section.classList.add("hidden");
    return;
  }

  section.classList.remove("hidden");
  container.innerHTML = "";

  // Grouping logic: movie -> standalone, tv/anime -> group by show title (Clean Continue Watching)
  const grouped = [];
  const seenShows = new Set();

  const sortedHistory = [...state.watchHistory]
    .map(normalizeWatchProgress)
    .filter((item) => item.type !== "livetv")
    .sort((a, b) => b.lastWatchedAt - a.lastWatchedAt);

  sortedHistory.forEach((item) => {
    if (item.type === "movie") {
      grouped.push(item);
    } else {
      const showKey = item.showTitle || item.title;
      if (!seenShows.has(showKey)) {
        seenShows.add(showKey);
        grouped.push(item);
      }
    }
  });

  grouped.forEach((item) => {
    const card = document.createElement("div");
    card.className =
      "media-card bg-brandSec rounded-xl border border-white/[0.04] p-2 hover:border-brandCyan/20 cursor-pointer text-left relative";
    card.onclick = () => showContinueWatchingSheet(item);

    const progressPercent = Math.round((item.progress || 0) * 100);
    let subtitle = item.type.toUpperCase();
    if (item.type === "tv" || item.type === "anime") {
      subtitle = `S${item.season} E${item.episode}`;
    }

    card.innerHTML = `
      <div class="relative aspect-[2/3] rounded-lg overflow-hidden bg-brandTert mb-2">
        <img src="${item.poster}" alt="${item.title}" class="w-full h-full object-cover" loading="lazy" onerror="this.onerror=null; this.src='https://ui-avatars.com/api/?background=111&color=fff&name=Media'">
        <div class="absolute bottom-0 left-0 right-0 h-1.5 bg-black/60">
          <div class="bg-brandCyan h-full" style="width: ${progressPercent}%"></div>
        </div>
        <span class="absolute top-1.5 right-1.5 bg-cyan-950/80 border border-brandCyan/20 text-brandCyan font-extrabold text-[9px] px-1.5 py-0.5 rounded">
          ${progressPercent}%
        </span>
      </div>
      <div class="px-1 space-y-0.5">
        <h4 class="text-xs font-bold text-gray-200 truncate leading-snug">${item.showTitle || item.title}</h4>
        <div class="flex items-center justify-between text-[10px] text-gray-500 font-medium">
          <span>${subtitle}</span>
          <span class="text-[9px] text-brandCyan bg-cyan-950/15 border border-brandCyan/10 px-1 rounded uppercase tracking-wider">${item.type}</span>
        </div>
      </div>
    `;
    container.appendChild(card);
  });
  lucide.createIcons();
}

function saveWatchProgress(item, options = {}) {
  const { syncRemote = true } = options;
  if (!item || !item.itemId) return;

  const next = [item];
  next.push(
    ...(state.watchHistory || []).filter((h) => h && h.itemId !== item.itemId),
  );
  state.watchHistory = next.slice(0, 30);

  localStorage.setItem(
    "omni_watch_history",
    JSON.stringify(state.watchHistory),
  );
  renderContinueWatching();

  if (syncRemote && state.traktToken) {
    pushToTrakt();
  }
}

function clearWatchHistory() {
  state.watchHistory = [];
  localStorage.setItem("omni_watch_history", "[]");
  renderContinueWatching();

  if (state.traktToken) {
    pushToTrakt();
  }
  window.electron.showNotification(
    "History Cleared",
    "Local and cloud watch history has been purged.",
  );
}

async function resumeWatchProgress(rawItem) {
  // Backward-compatible alias: card taps now use showContinueWatchingSheet.
  await openContinueWatchingDetails(rawItem);
}

async function pullFromTrakt() {
  if (!state.traktToken) return;

  await ensureFreshTraktToken();
  if (!state.traktToken) return;

  try {
    const listsUrl = "https://api.trakt.tv/users/me/lists";
    const headers = {
      "Content-Type": "application/json",
      Authorization: `Bearer ${state.traktToken}`,
      "trakt-api-version": "2",
      "trakt-api-key": state.traktClientId,
    };

    const res = await appFetch(listsUrl, "GET", headers);
    if (!res.ok) throw new Error("Could not fetch Trakt lists");

    const lists = JSON.parse(res.html);
    const syncList = lists.find((l) => l.name === "Omniverse Sync");
    if (syncList && syncList.description) {
      const payloadB64 = syncList.description.trim();
      const decodedString = decodeURIComponent(escape(atob(payloadB64)));
      const backup = JSON.parse(decodedString);

      if (backup.watch_history && Array.isArray(backup.watch_history)) {
        mergeWatchHistory(backup.watch_history);
      }

      if (backup.pixeldrain_api_key && !state.pixeldrainApiKey) {
        state.pixeldrainApiKey = backup.pixeldrain_api_key;
        localStorage.setItem("omni_pixeldrain_key", backup.pixeldrain_api_key);
      }
      if (backup.tmdb_token && !state.tmdbToken) {
        state.tmdbToken = backup.tmdb_token;
        localStorage.setItem("omni_tmdb_token", backup.tmdb_token);
      }
      if (backup.tvdb_api_key && !state.tvdbApiKey) {
        state.tvdbApiKey = backup.tvdb_api_key;
        localStorage.setItem("omni_tvdb_key", backup.tvdb_api_key);
      }
      if (backup.tvdb_pin && !state.tvdbPin) {
        state.tvdbPin = backup.tvdb_pin;
        localStorage.setItem("omni_tvdb_pin", backup.tvdb_pin);
      }
      if (backup.anilist_access_token && !state.anilistAccessToken) {
        state.anilistAccessToken = backup.anilist_access_token;
        localStorage.setItem("omni_anilist_token", backup.anilist_access_token);
      }
      loadSavedPreferences();
    }
  } catch (err) {
    console.error("Trakt pull error: ", err);
  }
}

function mergeWatchHistory(remoteHistory) {
  const localMap = new Map(state.watchHistory.map((h) => [h.itemId, h]));

  remoteHistory.forEach((remoteItem) => {
    const localItem = localMap.get(remoteItem.itemId);
    if (!localItem || remoteItem.lastWatchedAt > localItem.lastWatchedAt) {
      localMap.set(remoteItem.itemId, remoteItem);
    }
  });

  state.watchHistory = Array.from(localMap.values())
    .sort((a, b) => (Number(b.lastWatchedAt) || 0) - (Number(a.lastWatchedAt) || 0))
    .slice(0, 30);
  localStorage.setItem(
    "omni_watch_history",
    JSON.stringify(state.watchHistory),
  );
  renderContinueWatching();
}

let isPushing = false;
async function pushToTrakt() {
  if (!state.traktToken || isPushing) return;

  await ensureFreshTraktToken();
  if (!state.traktToken || isPushing) return;
  isPushing = true;

  try {
    const listsUrl = "https://api.trakt.tv/users/me/lists";
    const headers = {
      "Content-Type": "application/json",
      Authorization: `Bearer ${state.traktToken}`,
      "trakt-api-version": "2",
      "trakt-api-key": state.traktClientId,
    };

    const res = await appFetch(listsUrl, "GET", headers);
    if (!res.ok) throw new Error("Could not check lists");

    const lists = JSON.parse(res.html);
    const syncList = lists.find((l) => l.name === "Omniverse Sync");

    const payload = {
      version: 1,
      pixeldrain_api_key: state.pixeldrainApiKey,
      trakt_client_id: state.traktClientId,
      trakt_client_secret: state.traktClientSecret,
      tmdb_token: state.tmdbToken,
      tvdb_api_key: state.tvdbApiKey,
      tvdb_pin: state.tvdbPin,
      anilist_access_token: state.anilistAccessToken,
      watch_history: state.watchHistory,
    };

    const payloadB64 = btoa(
      unescape(encodeURIComponent(JSON.stringify(payload))),
    );

    const body = {
      name: "Omniverse Sync",
      description: payloadB64,
      privacy: "private",
    };

    if (syncList) {
      // PUT request to update list
      await appFetch(
        `https://api.trakt.tv/users/me/lists/${syncList.ids.trakt}`,
        "PUT",
        headers,
        body,
      );
    } else {
      // POST request to create list
      await appFetch(
        "https://api.trakt.tv/users/me/lists",
        "POST",
        headers,
        body,
      );
    }
  } catch (err) {
    console.error("Trakt push error: ", err);
  } finally {
    isPushing = false;
  }
}

function showSyncProgressModal() {
  const existing = document.getElementById("sync-progress-modal");
  if (existing) existing.remove();

  const modal = document.createElement("div");
  modal.id = "sync-progress-modal";
  modal.className =
    "fixed inset-0 z-[10000] detail-modal-overlay flex items-center justify-center p-6";
  modal.innerHTML = `
    <div class="detail-modal-card w-full max-w-sm p-6 rounded-2xl space-y-6 text-center bg-brandSec border border-white/[0.04] animate-fade-in shadow-2xl">
      <div class="flex flex-col items-center gap-3">
        <div class="w-12 h-12 rounded-full bg-cyan-950/40 border border-brandCyan/30 flex items-center justify-center text-brandCyan">
          <i data-lucide="refresh-cw" class="w-6 h-6 animate-spin"></i>
        </div>
        <h2 class="font-extrabold text-lg text-white">Synchronizing Cloud</h2>
        <p id="sync-modal-status" class="text-xs text-gray-400 leading-relaxed">Initializing secure handshake...</p>
      </div>

      <div class="space-y-2">
        <div class="w-full bg-brandDark/50 rounded-full h-2 overflow-hidden border border-white/[0.02]">
          <div id="sync-modal-progress-bar" class="bg-brandCyan h-full transition-all duration-300" style="width: 0%"></div>
        </div>
        <div class="flex justify-between text-[10px] text-gray-500 font-extrabold uppercase tracking-wider">
          <span>Trakt Sync</span>
          <span id="sync-modal-percentage">0%</span>
        </div>
      </div>
    </div>
  `;
  document.body.appendChild(modal);
  lucide.createIcons();
}

function updateSyncProgress(pct, statusText) {
  const bar = document.getElementById("sync-modal-progress-bar");
  const pctLabel = document.getElementById("sync-modal-percentage");
  const status = document.getElementById("sync-modal-status");

  if (bar) bar.style.width = `${pct}%`;
  if (pctLabel) pctLabel.textContent = `${pct}%`;
  if (status) status.textContent = statusText;
}

function hideSyncProgressModal() {
  const modal = document.getElementById("sync-progress-modal");
  if (modal) {
    modal.classList.add("animate-fade-out");
    setTimeout(() => modal.remove(), 250);
  }
}

// Force Sync Action trigger (Unified Cloud Sync)
async function forceSyncNow() {
  const icon = document.getElementById("icon-force-sync");
  const btn = document.getElementById("btn-force-sync");
  if (icon) icon.classList.add("animate-spin");
  if (btn) {
    btn.disabled = true;
    btn.classList.add("opacity-70");
    btn.innerHTML = `<i data-lucide="refresh-cw" id="icon-force-sync" class="w-3.5 h-3.5 animate-spin"></i> Syncing...`;
  }

  showSyncProgressModal();
  updateSyncProgress(10, "Establishing connection to Trakt...");
  await new Promise((resolve) => setTimeout(resolve, 600));

  try {
    window.electron.showNotification(
      "Cloud Sync Initiated",
      "Pulling latest watch progress and profiles from Trakt...",
    );
  } catch (err) {
    console.warn("Failed to show cloud sync notification:", err);
  }

  try {
    if (state.traktToken) {
      updateSyncProgress(30, "Downloading watch history and settings...");
      await pullFromTrakt();
      updateSyncProgress(60, "Merging profiles and credentials...");
      await new Promise((resolve) => setTimeout(resolve, 500));
    } else {
      updateSyncProgress(50, "Skipping Trakt (not authenticated)...");
      await new Promise((resolve) => setTimeout(resolve, 400));
    }

    updateSyncProgress(75, "Re-rendering catalog feeds and trending lists...");
    await renderCatalogFeeds();

    updateSyncProgress(90, "Updating Continue Watching shelf...");
    renderContinueWatching();
    await new Promise((resolve) => setTimeout(resolve, 450));

    updateSyncProgress(100, "Synchronized!");
    await new Promise((resolve) => setTimeout(resolve, 500));

    try {
      window.electron.showNotification(
        "Sync Completed",
        "Dynamic catalogs and continue-watching watch history have been successfully synchronized!",
      );
    } catch (err) {
      console.warn("Failed to show sync completed notification:", err);
    }
  } catch (err) {
    console.error("Force sync failed:", err);
    window.electron.showNotification(
      "Sync Warning",
      "Sync finished with some network warnings.",
    );
  } finally {
    hideSyncProgressModal();
    if (icon) icon.classList.remove("animate-spin");
    if (btn) {
      btn.disabled = false;
      btn.classList.remove("opacity-70");
      btn.innerHTML = `<i data-lucide="refresh-cw" id="icon-force-sync" class="w-3.5 h-3.5"></i> Force Sync Now`;
    }
    lucide.createIcons();
  }
}

async function checkAnimeServerLatencies(btn) {}

  const originalHtml = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = `<i data-lucide="refresh-cw" class="w-4 h-4 animate-spin inline mr-1"></i> Testing...`;
  if (window.lucide) lucide.createIcons();

  container.classList.remove("hidden");
  container.innerHTML = `<div class="flex items-center gap-2 text-brandCyan"><i data-lucide="loader" class="w-4 h-4 animate-spin"></i><span>📡 Pinging ani-cli anime sources...</span></div>`;
  if (window.lucide) lucide.createIcons();

  const sites = [
    { name: "AllManga", url: "https://allmanga.to" },
    { name: "AllAnime API", url: "https://api.allanime.day/api" },
  ];

  let htmlResults = `<div class="space-y-2">`;
  let fastestGeneralDomain = null;
  let minGeneralLatency = Infinity;

  for (const s of sites) {
    const start = Date.now();
    let isUp = false;
    let statusText = "Offline";
    try {
      const res = await appFetch(s.url);
      isUp = res.ok;
      statusText = res.ok ? "Online" : `HTTP ${res.status}`;
    } catch (_) {}

    const duration = Date.now() - start;
    if (isUp) {
      let details = `${duration} ms <span class="text-brandCyan font-semibold">(ani-cli path)</span>`;
      if (duration < minGeneralLatency) {
        minGeneralLatency = duration;
        fastestGeneralDomain = s.url;
      }

      htmlResults += `<div class="flex justify-between items-center py-1 border-b border-white/[0.02]">
        <span class="text-gray-300 font-bold">${s.name} <span class="text-[9px] text-gray-500 font-medium">(${s.url.replace("https://", "")})</span></span>
        <span class="text-emerald-400 font-mono">${details}</span>
      </div>`;
    } else {
      htmlResults += `<div class="flex justify-between items-center py-1 border-b border-white/[0.02]">
        <span class="text-gray-300 font-bold">${s.name} <span class="text-[9px] text-gray-500 font-medium">(${s.url.replace("https://", "")})</span></span>
        <span class="text-red-500 font-bold uppercase">${statusText}</span>
      </div>`;
    }
  }



  if (fastestGeneralDomain) {
    htmlResults += `<div class="mt-2 p-2.5 text-center text-xs font-bold text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 rounded-lg flex items-center justify-center gap-2">
      <i data-lucide="activity" class="w-4 h-4"></i>
      <span>Fastest ani-cli endpoint: ${fastestGeneralDomain.replace("https://", "")} (${minGeneralLatency} ms)</span>
    </div>`;
  }

  htmlResults += `</div>`;
  container.innerHTML = htmlResults;
  if (window.lucide) lucide.createIcons();

  btn.disabled = false;
  btn.innerHTML = originalHtml;
  if (window.lucide) lucide.createIcons();
}

window.omniLogs = [];
window.omniLog = function (category, message) {
  const timestamp = new Date().toISOString().substring(11, 19);
  const formatted = `[${timestamp}][${category}] ${message}`;
  window.omniLogs.push(formatted);
  if (window.omniLogs.length > 500) {
    window.omniLogs.shift();
  }
  console.log(formatted);
  
  const logContainer = document.getElementById("debug-log-view");
  if (logContainer) {
    // If it contains the placeholder, remove it
    if (logContainer.querySelector(".italic")) {
      logContainer.innerHTML = "";
    }
    const el = document.createElement("div");
    el.className = "py-0.5 border-b border-white/[0.01] hover:bg-white/[0.02] break-all font-mono text-[10px]";
    
    const lowerCategory = category.toLowerCase();
    if (lowerCategory.includes("err") || lowerCategory.includes("fail") || lowerCategory.includes("reject")) {
      el.className += " text-red-400";
    } else if (lowerCategory.includes("warn")) {
      el.className += " text-amber-400";
    } else if (lowerCategory.includes("success") || lowerCategory.includes("ok") || lowerCategory.includes("pass")) {
      el.className += " text-emerald-400";
    } else if (lowerCategory.includes("info") || lowerCategory.includes("pinger") || lowerCategory.includes("speed")) {
      el.className += " text-brandCyan";
    } else {
      el.className += " text-gray-300";
    }
    
    el.textContent = formatted;
    logContainer.appendChild(el);
    logContainer.scrollTop = logContainer.scrollHeight;
  }
};

function clearDebugLogs() {
  window.omniLogs = [];
  const logContainer = document.getElementById("debug-log-view");
  if (logContainer) {
    logContainer.innerHTML = `<div class="text-gray-500 italic">Console cleared. Waiting for pipeline transactions...</div>`;
  }
}

function copyDebugLogs() {
  const text = window.omniLogs.join("\n");
  navigator.clipboard.writeText(text).then(() => {
    if (window.electron && window.electron.showNotification) {
      window.electron.showNotification("Console Copied", "Debug logs successfully copied to your clipboard!");
    }
  }).catch((err) => {
    console.error("Failed to copy logs to clipboard: ", err);
  });
}

// Global Keyboard Shortcuts & Rail Kinetic Physics
document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "f") {
    e.preventDefault();
    switchScreen("search");
    setTimeout(() => {
      const searchInput = document.getElementById("search-input");
      if (searchInput) searchInput.focus();
    }, 50);
  } else if (e.key === "Escape") {
    const detailModal = document.getElementById("media-detail-modal");
    if (detailModal && !detailModal.classList.contains("hidden")) {
      e.preventDefault();
      if (typeof closeMediaDetail === "function") closeMediaDetail();
    }
  }
});

// Horizontal mouse wheel scrolling for content rails
document.addEventListener("wheel", (e) => {
  const rail = e.target.closest(".horizontal-rail");
  if (rail && e.deltaY !== 0 && !e.shiftKey) {
    rail.scrollLeft += e.deltaY * 1.5;
  }
}, { passive: true });

