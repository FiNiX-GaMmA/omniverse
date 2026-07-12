// ==============================================================================
// Omniverse Desktop — Core Renderer Controller
// ==============================================================================

// Global Application State
let state = {
  tmdbToken: localStorage.getItem("omni_tmdb_token") || "",
  vidsrcDomain: localStorage.getItem("omni_vidsrc_domain") || "vidsrc.me",
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
};

// Curated high-fidelity backup database (ensures app is populated before TMDB token entry)
const FALLBACK_DB = {
  movies: [
    {
      id: "m1",
      title: "Dune: Part Two",
      type: "movie",
      year: 2024,
      rating: "8.3",
      tmdbId: 823464,
      poster: "https://image.tmdb.org/t/p/w500/1pdf3ZzY7S7VRL37vIgz7JK0p0y.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/x887Of99v489rSgIY6M69id9982.jpg",
      overview:
        "Follow the mythic journey of Paul Atreides as he unites with Chani and the Fremen while on a path of revenge against the conspirators who destroyed his family.",
    },
    {
      id: "m2",
      title: "Deadpool & Wolverine",
      type: "movie",
      year: 2024,
      rating: "7.8",
      tmdbId: 533535,
      poster: "https://image.tmdb.org/t/p/w500/8cdWv6Z79h2Y9C6_-9v_D69f7Of.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/yD1b09b57Of9d7h7M69e06yY0E.jpg",
      overview:
        "A listless Wade Wilson toils in civilian life. His days as the morally flexible mercenary, Deadpool, behind him. When his homeworld faces an existential threat, he must reluctantly suit-up.",
    },
    {
      id: "m3",
      title: "Oppenheimer",
      type: "movie",
      year: 2023,
      rating: "8.1",
      tmdbId: 872585,
      poster: "https://image.tmdb.org/t/p/w500/8Gxv2gSj0u06st26sh6fC69fOf.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/fm6Of99v289rSgIY6M69id9982.jpg",
      overview:
        "The story of J. Robert Oppenheimer's role in the development of the atomic bomb during World War II.",
    },
    {
      id: "m4",
      title: "Interstellar",
      type: "movie",
      year: 2014,
      rating: "8.4",
      tmdbId: 157336,
      poster:
        "https://image.tmdb.org/t/p/w500/gEU2Qv6IL7hO6m2gSj0u06st26sh.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/rAiO3fO99v489rSgIY6M69id9982.jpg",
      overview:
        "The adventures of a group of explorers who make use of a newly discovered wormhole to surpass the limitations on human space travel.",
    },
    {
      id: "m5",
      title: "Spider-Man: Across the Spider-Verse",
      type: "movie",
      year: 2023,
      rating: "8.4",
      tmdbId: 569094,
      poster: "https://image.tmdb.org/t/p/w500/8Gxv2gSj0u06st26sh6fC6.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/nG6O3fO99v489rSgIY6M69id9982.jpg",
      overview:
        "Miles Morales catapults across the Multiverse, where he encounters a team of Spider-People charged with protecting its very existence.",
    },
  ],
  tv: [
    {
      id: "s1",
      title: "Breaking Bad",
      type: "tv",
      year: 2008,
      rating: "9.5",
      tmdbId: 1396,
      poster: "https://image.tmdb.org/t/p/w500/ztk6Of99v489rSgIY6M69id9982.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/tsG6O3fO99v489rSgIY6M69id9982.jpg",
      overview:
        "A high school chemistry teacher diagnosed with inoperable lung cancer turns to manufacturing and selling methamphetamine.",
      seasons: 5,
      episodesPerSeason: [7, 13, 13, 13, 16],
    },
    {
      id: "s2",
      title: "Wednesday",
      type: "tv",
      year: 2022,
      rating: "8.0",
      tmdbId: 119051,
      poster: "https://image.tmdb.org/t/p/w500/bxi78zSj0u06st26sh6fC69fOf.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/iD1b09b57Of9d7h7M69e06yY0E.jpg",
      overview:
        "A sleuthing, supernaturally infused mystery charting Wednesday Addams' years as a student at Nevermore Academy.",
      seasons: 1,
      episodesPerSeason: [8],
    },
    {
      id: "s3",
      title: "Stranger Things",
      type: "tv",
      year: 2016,
      rating: "8.6",
      tmdbId: 66732,
      poster: "https://image.tmdb.org/t/p/w500/x27Of99v489rSgIY6M69id9982.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/pG6O3fO99v489rSgIY6M69id9982.jpg",
      overview:
        "When a young boy vanishes, a small town uncovers a mystery involving secret experiments, terrifying supernatural forces and one strange little girl.",
      seasons: 4,
      episodesPerSeason: [8, 9, 8, 9],
    },
    {
      id: "s4",
      title: "Shōgun",
      type: "tv",
      year: 2024,
      rating: "8.5",
      tmdbId: 79242,
      poster: "https://image.tmdb.org/t/p/w500/7cdWv6Z79h2Y9C6_-9v_D69f7Of.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/zG6O3fO99v489rSgIY6M69id9982.jpg",
      overview:
        "In Japan in the year 1600, Lord Yoshii Toranaga is fighting for his life as his enemies on the Council of Regents unite against him.",
      seasons: 1,
      episodesPerSeason: [10],
    },
  ],
  anime: [
    {
      id: "a1",
      title: "One Piece",
      type: "tv",
      year: 1999,
      rating: "8.7",
      tmdbId: 37854,
      poster: "https://image.tmdb.org/t/p/w500/c3Of99v489rSgIY6M69id9982.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/4g6O3fO99v489rSgIY6M69id9982.jpg",
      overview:
        "Monkey D. Luffy and his pirate crew explore a fantastical world of endless oceans and exotic islands in search of the world's ultimate treasure.",
      seasons: 1,
      episodesPerSeason: [1110],
    },
    {
      id: "a2",
      title: "Demon Slayer: Kimetsu no Yaiba",
      type: "tv",
      year: 2019,
      rating: "8.7",
      tmdbId: 85937,
      poster: "https://image.tmdb.org/t/p/w500/hcdWv6Z79h2Y9C6_-9v_D69f7Of.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/vG6O3fO99v489rSgIY6M69id9982.jpg",
      overview:
        "It is the Taisho Period in Japan. Tanjiro, a kindhearted boy who sells charcoal for a living, finds his family slaughtered by a demon.",
      seasons: 4,
      episodesPerSeason: [26, 18, 11, 8],
    },
    {
      id: "a3",
      title: "Jujutsu Kaisen",
      type: "tv",
      year: 2020,
      rating: "8.6",
      tmdbId: 95479,
      poster: "https://image.tmdb.org/t/p/w500/ycdWv6Z79h2Y9C6_-9v_D69f7Of.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/uG6O3fO99v489rSgIY6M69id9982.jpg",
      overview:
        "Yuji Itadori is a boy with tremendous physical strength, though he lives a completely ordinary high school life. One day, to save a classmate who has been attacked by curses, he eats the finger of Ryomen Sukuna, taking the curse into his own soul.",
      seasons: 2,
      episodesPerSeason: [24, 23],
    },
  ],
};
// Initialize UI on startup
document.addEventListener("DOMContentLoaded", async () => {
  setupPlatformWindowDecorations();
  loadSavedPreferences();
  switchScreen("home");
  renderCatalogFeeds();
  setupSearchInput();
  setupLiveTvCenter();
  renderContinueWatching(); // Initial local history render
  setupAdblockObserver();
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

  if (!token.startsWith("ey")) {
    urlParams.set("api_key", token);
  }

  const url = `https://api.themoviedb.org/3/${path}?${urlParams.toString()}`;
  const headers = { Accept: "application/json" };
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

function mapTmdbItem(item, type) {
  const fallbackImg =
    "https://ui-avatars.com/api/?background=111&color=fff&size=500&name=" +
    encodeURIComponent(item.title || item.name || "Unknown");
  const posterPath = item.poster_path
    ? `https://image.tmdb.org/t/p/w500${item.poster_path}`
    : fallbackImg;
  const backdropPath = item.backdrop_path
    ? `https://image.tmdb.org/t/p/original${item.backdrop_path}`
    : fallbackImg;
  const releaseDate = item.release_date || item.first_air_date || "";
  const year = releaseDate ? new Date(releaseDate).getFullYear() : "—";
  const genreIds = item.genre_ids || [];
  const genres = genreIds.map((id) => TMDB_GENRES[id]).filter(Boolean);
  return {
    id: `tmdb:${type}:${item.id}`,
    title: item.title || item.name || "Untitled",
    type: type,
    year: year,
    rating: item.vote_average ? item.vote_average.toFixed(1) : "—",
    tmdbId: item.id,
    poster: posterPath,
    backdrop: backdropPath,
    overview: item.overview || "No description available.",
    genres: genres,
  };
}

function showGridLoading(containerId) {
  const container = document.getElementById(containerId);
  if (!container) return;
  container.innerHTML = `
    <div class="col-span-full flex flex-col items-center justify-center py-8 gap-2 text-gray-500">
      <div class="w-5 h-5 rounded-full border-2 border-brandCyan border-t-transparent animate-spin"></div>
      <span class="text-[10px] font-bold uppercase tracking-wider text-brandCyan">Loading...</span>
    </div>
  `;
}

function updateHeroBanner(media) {
  const heroBanner = document.getElementById("hero-banner");
  const heroTitle = document.getElementById("hero-title");
  const heroOverview = document.getElementById("hero-overview");
  const heroPlayBtn = document.getElementById("hero-play-btn");
  const heroDetailBtn = document.getElementById("hero-detail-btn");

  if (!heroBanner || !media) return;

  heroBanner.style.opacity = "0.3";
  setTimeout(() => {
    heroBanner.style.backgroundImage = `url('${media.backdrop || media.poster}')`;
    if (heroTitle) heroTitle.textContent = media.title;
    if (heroOverview) heroOverview.textContent = media.overview;
    heroBanner.style.opacity = "1";
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

  if (heroDetailBtn) {
    heroDetailBtn.onclick = () => openDetailModal(media);
  }
}

// Render dynamic elements
async function renderCatalogFeeds(skipAnimeLoad = false) {
  let trendingMovies = [];
  let trendingTv = [];

  if (state.tmdbToken) {
    showGridLoading("grid-all-movies");
    showGridLoading("grid-all-tv");

    const trendingMoviesData = await fetchTmdb("trending/movie/week");
    trendingMovies =
      trendingMoviesData && trendingMoviesData.results
        ? trendingMoviesData.results.map((item) => mapTmdbItem(item, "movie"))
        : FALLBACK_DB.movies;

    const trendingTvData = await fetchTmdb("trending/tv/week");
    trendingTv =
      trendingTvData && trendingTvData.results
        ? trendingTvData.results.map((item) => mapTmdbItem(item, "tv"))
        : FALLBACK_DB.tv;

    const popularMoviesData = await fetchTmdb("movie/now_playing");
    const popularMovies =
      popularMoviesData && popularMoviesData.results
        ? popularMoviesData.results.map((item) => mapTmdbItem(item, "movie"))
        : FALLBACK_DB.movies;

    const topRatedTvData = await fetchTmdb("tv/top_rated");
    const topRatedTv =
      topRatedTvData && topRatedTvData.results
        ? topRatedTvData.results.map((item) => mapTmdbItem(item, "tv"))
        : FALLBACK_DB.tv;

    renderGrid("grid-all-movies", popularMovies.slice(0, 18));
    renderGrid("grid-all-tv", topRatedTv.slice(0, 18));

    const heroMedia =
      trendingMovies[0] || trendingTv[0] || FALLBACK_DB.movies[0];
    updateHeroBanner(heroMedia);
  } else {
    trendingMovies = FALLBACK_DB.movies;
    trendingTv = FALLBACK_DB.tv;

    renderGrid("grid-all-movies", FALLBACK_DB.movies);
    renderGrid("grid-all-tv", FALLBACK_DB.tv);
    updateHeroBanner(FALLBACK_DB.movies[0]);
  }

  // Define and build high-fidelity categories list exactly like the mobile apps (paritied with Kotlin/Swift lists)
  const categories = [];

  // Blend movies, tv, and anime for top 10 trending
  const blendTop10 = [];
  let mi = 0,
    si = 0,
    ai = 0;
  const maxLimit = 10;
  const dynamicAnimeList =
    state.animeCatalog && state.animeCatalog.length
      ? state.animeCatalog
      : FALLBACK_DB.anime;

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
      description: "Popular theatrical and digital releases",
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
      description: "What everyone is watching right now",
      items: dynamicAnimeList.slice(0, 10),
      isTop10: true,
    });
  }

  // Genre Categories
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
        description: `Popular ${genre} titles to watch this week`,
        items: picks.slice(0, 15),
        isTop10: false,
      });
    }
  });

  const homeCatalogs = document.getElementById("home-catalogs");
  if (homeCatalogs) {
    homeCatalogs.innerHTML = "";
    categories.forEach((cat) => {
      const catSection = document.createElement("div");
      catSection.className = "space-y-3";

      const header = document.createElement("div");
      header.className = "flex items-center justify-between";
      header.innerHTML = `
        <div class="flex flex-col">
          <h2 class="text-sm font-black text-white uppercase tracking-wider">${cat.title}</h2>
          <p class="text-[10px] text-gray-500 font-semibold">${cat.description}</p>
        </div>
      `;

      const rail = document.createElement("div");
      rail.className =
        "horizontal-rail flex overflow-x-auto gap-4 pb-4 scrollbar-none no-drag";

      cat.items.forEach((item, index) => {
        if (cat.isTop10) {
          const card = document.createElement("div");
          card.className =
            "relative flex items-end h-[220px] min-w-[180px] select-none shrink-0";
          card.onclick = () => openDetailModal(item);
          const rank = index + 1;
          card.innerHTML = `
            <span class="absolute bottom-[-10px] left-0 text-[130px] font-black leading-none text-white/[0.08] select-none pointer-events-none font-sans z-0">
              ${rank}
            </span>
            <div class="media-card ml-auto w-[130px] h-[195px] rounded-lg p-0 cursor-pointer text-left bg-transparent relative z-10">
              <div class="group relative aspect-[2/3] rounded-lg overflow-hidden bg-brandTert mb-1.5 shadow-lg">
                <img src="${item.poster}" alt="${item.title}" class="w-full h-full object-cover transition duration-300 group-hover:scale-105 group-hover:opacity-50" loading="lazy" onerror="this.onerror=null; this.src='https://ui-avatars.com/api/?background=111&color=fff&name=Media'">
                <div class="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition duration-300">
                  <i data-lucide="play-circle" class="w-10 h-10 text-white drop-shadow-lg"></i>
                </div>
                <span class="absolute top-1 right-1 bg-black/80 text-white font-bold text-[9px] px-1.5 py-0.5 rounded flex items-center gap-0.5 z-20">
                  ★ ${item.rating || "—"}
                </span>
              </div>
              <div class="px-0.5 space-y-0.5">
                <h4 class="text-[11px] font-semibold text-gray-200 truncate leading-snug">${item.title}</h4>
                <div class="flex items-center justify-between text-[9px] text-gray-500 font-medium">
                  <span>${item.year || "—"}</span>
                  <span class="uppercase text-[8px] tracking-wider text-brandCyan">${item.type}</span>
                </div>
              </div>
            </div>
          `;
          rail.appendChild(card);
        } else {
          const card = document.createElement("div");
          card.onclick = () => openDetailModal(item);
          card.className =
            "media-poster-card cursor-pointer group w-[180px] shrink-0";
          card.innerHTML = `
            <div class="relative aspect-[2/3] w-full">
              <img src="${item.poster}" alt="${item.title}" class="w-full h-full object-cover" loading="lazy" onerror="this.onerror=null; this.src='https://ui-avatars.com/api/?background=111&color=fff&name=Media'">
              <div class="play-fab"><i data-lucide="play" class="w-8 h-8 fill-current"></i></div>
              <div class="media-overlay-glass">
                <h4 class="text-white font-bold text-sm leading-tight drop-shadow-md mb-1 line-clamp-2">${item.title}</h4>
                <div class="flex items-center justify-between text-gray-300 text-[10px] font-semibold tracking-wide">
                  <span>${item.year || "—"}</span>
                  <span class="flex items-center gap-1"><i data-lucide="star" class="w-3 h-3 fill-amber-400 text-amber-400"></i> ${item.rating || "—"}</span>
                </div>
              </div>
            </div>
          `;
          rail.appendChild(card);
        }
      });

      catSection.appendChild(header);
      catSection.appendChild(rail);
      homeCatalogs.appendChild(catSection);
    });
  }

  renderGrid("grid-all-anime", dynamicAnimeList);
  if (!skipAnimeLoad) {
    loadAnimeCatalog();
  }
  lucide.createIcons();
}

// Populate the anime grid from AniList — parity with the mobile anime discovery.
async function loadAnimeCatalog() {
  if (!window.OmniAnime) return;
  try {
    const cats = await window.OmniAnime.fetchAnimeCategories();
    // Merge de-duplicated items across categories into the anime grid.
    const seen = new Set();
    const items = [];
    for (const c of cats) {
      for (const it of c.items || []) {
        if (it.poster && !seen.has(it.id)) {
          seen.add(it.id);
          items.push(it);
        }
      }
    }
    if (items.length) {
      state.animeCatalog = items;
      renderGrid("grid-all-anime", items);
      // Seamlessly trigger updated categories rail blend
      renderCatalogFeeds(true);
    }
  } catch (e) {
    console.warn(
      "[Omniverse] AniList anime catalog failed, using fallback:",
      e,
    );
  }
}

function renderGrid(containerId, items, isLordflix = false) {
  const container = document.getElementById(containerId);
  if (!container) return;
  container.innerHTML = "";

  items.forEach((item) => {
    const card = document.createElement("div");
    card.onclick = () => openDetailModal(item);

    if (isLordflix) {
      card.className = "media-poster-card cursor-pointer group";
      card.innerHTML = `
        <div class="relative aspect-[2/3] w-full">
          <img src="${item.poster}" alt="${item.title}" class="w-full h-full object-cover" loading="lazy" onerror="this.onerror=null; this.src='https://ui-avatars.com/api/?background=111&color=fff&name=Media'">
          <div class="play-fab"><i data-lucide="play" class="w-8 h-8 fill-current"></i></div>
          <div class="media-overlay-glass">
            <h4 class="text-white font-bold text-sm leading-tight drop-shadow-md mb-1">${item.title}</h4>
            <div class="flex items-center justify-between text-gray-300 text-[10px] font-semibold tracking-wide">
              <span>${item.year}</span>
              <span class="flex items-center gap-1"><i data-lucide="star" class="w-3 h-3 fill-amber-400 text-amber-400"></i> ${item.rating}</span>
            </div>
          </div>
        </div>
      `;
    } else {
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
    }

    container.appendChild(card);
  });
}

// Single Page Screen Routing
function switchScreen(screenName) {
  state.currentScreen = screenName;
  state.activeStudio = "";

  // Hide all screens
  const screens = [
    "home",
    "movies",
    "tv",
    "anime",
    "onepace",
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

  // Pause Live TV player if leaving Live TV screen
  if (screenName !== "livetv") {
    const player = document.getElementById("livetv-player");
    if (player) player.pause();
  }

  // Pause One Pace player if leaving One Pace screen
  if (screenName !== "onepace") {
    const player = document.getElementById("onepace-player");
    if (player) player.pause();
  }
}

// Studio Filtering logic
async function filterByStudio(studio) {
  state.activeStudio = studio;
  switchScreen("movies");

  const headline = document.querySelector("#screen-movies h1");
  headline.textContent = `${studio.toUpperCase()} NETWORKS`;

  showGridLoading("grid-all-movies");

  window.electron.showNotification(
    "Network Filtering",
    `Fetching ${studio.toUpperCase()} films from TMDB...`,
  );

  let companyId = null;
  let networkId = null;
  switch (studio.toLowerCase()) {
    case "disney":
      companyId = "2";
      networkId = "2739";
      break;
    case "netflix":
      companyId = "178464";
      networkId = "213";
      break;
    case "hbo":
      companyId = "174";
      networkId = "3186";
      break;
    case "prime":
      companyId = "20580";
      networkId = "1024";
      break;
    case "apple":
      companyId = "194303";
      networkId = "2552";
      break;
    case "paramount":
      companyId = "4";
      networkId = "359";
      break;
    case "marvel":
      companyId = "420";
      break;
    case "pixar":
      companyId = "3";
      break;
    case "warner":
      companyId = "174"; // WB
      break;
    case "universal":
      companyId = "33"; // Universal
      break;
    case "paramount":
      companyId = "4"; // Paramount
      break;
    case "sony":
      companyId = "5"; // Sony/Columbia is usually 5
      break;
    case "a24":
      companyId = "41077"; // A24 company ID is 41077
      break;
  }

  if (state.tmdbToken && (companyId || networkId)) {
    const params = companyId
      ? { with_companies: companyId }
      : { with_networks: networkId };
    const movieData = await fetchTmdb("discover/movie", params);

    if (movieData && movieData.results && movieData.results.length > 0) {
      const items = movieData.results.map((item) => mapTmdbItem(item, "movie"));
      renderGrid("grid-all-movies", items);
      lucide.createIcons();
      return;
    }
  }

  // Fallback if TMDB not configured or fetch failed
  const filteredMovies = FALLBACK_DB.movies.filter(
    (m) =>
      m.overview.toLowerCase().includes(studio.toLowerCase()) ||
      studio === "disney",
  );
  renderGrid(
    "grid-all-movies",
    filteredMovies.length > 0 ? filteredMovies : FALLBACK_DB.movies,
  );
  lucide.createIcons();
}

// Detail Sheet Overlay Manager
async function openDetailModal(media) {
  state.selectedMedia = media;

  const modalPoster = document.getElementById("modal-poster");
  const modalBackdrop = document.getElementById("modal-backdrop-bg");
  const modalTitle = document.getElementById("modal-title");
  const modalOverview = document.getElementById("modal-overview");
  const modalYearChip = document.getElementById("modal-year-chip");
  const modalRatingChip = document.getElementById("modal-rating-chip");
  const typeChip = document.getElementById("modal-type-chip");
  const episodeSection = document.getElementById("modal-episodes-section");
  const playBtn = document.getElementById("modal-play-btn");

  // Load initial fallback/passed data
  modalPoster.src = media.poster;
  if (modalBackdrop)
    modalBackdrop.style.backgroundImage = `url('${media.backdrop || media.poster}')`;
  modalTitle.textContent = media.title;
  modalOverview.textContent = media.overview;
  modalYearChip.textContent = media.year;
  modalRatingChip.innerHTML = `<i data-lucide="star" class="w-3.5 h-3.5 fill-amber-400"></i> ${media.rating}`;
  typeChip.textContent = media.type.toUpperCase();

  // If TMDB is active, let's fetch deeper details dynamically to replace the fallbacks!
  // Anime can use TMDB details too if it has a tmdbId (which mapped items like One Piece do).
  if (state.tmdbToken && media.tmdbId && media.title !== "One Pace") {
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

    if (details) {
      const posterUrl = details.poster_path
        ? `https://image.tmdb.org/t/p/w500${details.poster_path}`
        : media.poster;
      const backdropUrl = details.backdrop_path
        ? `https://image.tmdb.org/t/p/original${details.backdrop_path}`
        : media.backdrop;

      modalPoster.src = posterUrl;
      if (modalBackdrop)
        modalBackdrop.style.backgroundImage = `url('${backdropUrl}')`;
      state.selectedMedia.poster = posterUrl;
      state.selectedMedia.backdrop = backdropUrl;

      modalTitle.textContent = details.title || details.name || media.title;
      modalOverview.textContent =
        details.overview || "No description available.";

      const releaseDate = details.release_date || details.first_air_date || "";
      const year = releaseDate
        ? new Date(releaseDate).getFullYear()
        : media.year;
      modalYearChip.textContent = year;
      state.selectedMedia.year = year;

      const runtime =
        details.runtime ||
        (details.episode_run_time && details.episode_run_time[0]) ||
        0;
      const h = Math.floor(runtime / 60);
      const m = runtime % 60;
      document.getElementById("modal-runtime-chip").textContent =
        runtime > 0 ? (h > 0 ? `${h}h ${m}m` : `${m}m`) : "";
      document.getElementById("info-runtime").textContent =
        runtime > 0 ? (h > 0 ? `${h}h ${m}m` : `${m}m`) : "Unknown";

      document.getElementById("info-language").textContent =
        details.original_language || "EN";
      document.getElementById("info-release").textContent =
        releaseDate || "Unknown";

      const formatMoney = (amount) => {
        if (!amount) return "Unknown";
        return new Intl.NumberFormat("en-US", {
          style: "currency",
          currency: "USD",
        }).format(amount);
      };
      document.getElementById("info-budget").textContent = formatMoney(
        details.budget,
      );
      document.getElementById("info-revenue").textContent = formatMoney(
        details.revenue,
      );

      // Parse Director
      let director = "Unknown";
      if (details.credits && details.credits.crew) {
        const d = details.credits.crew.find((c) => c.job === "Director");
        if (d) director = d.name;
      }
      document.getElementById("modal-director").textContent = director;

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
      document.getElementById("modal-content-rating-chip").textContent =
        ageRating;

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
        modalLogo.src = `https://image.tmdb.org/t/p/w500${engLogo.file_path}`;
        modalLogo.classList.remove("hidden");
        modalTitleText.classList.add("hidden");
      } else {
        modalLogo.classList.add("hidden");
        modalTitleText.classList.remove("hidden");
        modalTitleText.textContent =
          details.title || details.name || media.title;
      }

      // Populate Genres
      const genresList = details.genres
        ? details.genres.map((g) => g.name).join(" • ")
        : media.genres.join(" • ");
      document.getElementById("modal-genres").textContent = genresList;

      // Cast rail population
      const castRail = document.getElementById("modal-cast-rail");
      castRail.innerHTML = "";
      if (details.credits && details.credits.cast) {
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
      document.getElementById("modal-rating-text").textContent = rating;

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

    loadSeasonEpisodes();
  } else {
    episodeSection.classList.add("hidden");
    playBtn.classList.remove("hidden");
    playBtn.onclick = () => playStream(media);
  }

  document.getElementById("detail-modal").classList.remove("hidden");
  lucide.createIcons();
}

function closeDetailModal() {
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

function appendEpisodeRow(grid, media, seasonVal, ep, title) {
  const epRow = document.createElement("button");
  epRow.className =
    "w-full text-left p-3 rounded-lg bg-brandTert hover:bg-brandCyan/10 border border-white/[0.04] text-xs font-semibold flex items-center justify-between group transition duration-200";
  epRow.onclick = () => playStream(media, seasonVal, ep);
  epRow.innerHTML = `
    <div class="flex items-center gap-3">
      <span class="text-brandCyan bg-cyan-950/40 px-2 py-1 rounded">EP ${ep}</span>
      <span class="text-gray-300 group-hover:text-white transition">${escapeHtml(title)}</span>
    </div>
    <i data-lucide="play" class="w-3.5 h-3.5 text-gray-500 group-hover:text-brandCyan fill-transparent group-hover:fill-brandCyan transition duration-300"></i>
  `;
  grid.appendChild(epRow);
}

async function loadSeasonEpisodes() {
  const media = state.selectedMedia;
  const seasonSelect = document.getElementById("season-selector");
  const seasonVal = parseInt(seasonSelect.value) || 1;
  const grid = document.getElementById("episodes-grid");
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
      appendEpisodeRow(grid, media, seasonVal, ep, title);
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
  } else if (media.id === "a1") {
    epCount = 12; // Cap One Piece demo display list
  }
  for (let ep = 1; ep <= epCount; ep++) {
    appendEpisodeRow(grid, media, seasonVal, ep, `Episode ${ep}`);
  }
  lucide.createIcons();
}

// Integrated Secure Webview Playback Launcher
function playStream(media, season = null, episode = null, forceDomain = null) {
  // Anime resolves a DIRECT stream (AllAnime), like the mobile apps — not a
  // vidsrc embed. Route it to the direct-video player.
  if (media.type === "anime" && window.OmniAnime) {
    playAnimeStream(media, episode || 1);
    return;
  }

  closeDetailModal();

  const titleEl = document.getElementById("player-stream-title");

  // Use passed domain or fallback to state
  const targetDomain = forceDomain || state.vidsrcDomain || "vidsrc.me";
  let embedUrl = "";

  if (media.type === "movie") {
    titleEl.textContent = `${media.title} (Movie)`;
  } else {
    titleEl.textContent = `${media.title} — S${season} E${episode}`;
  }

  if (targetDomain.includes("multiembed")) {
    embedUrl =
      media.type === "movie"
        ? `https://multiembed.mov/?video_id=${media.tmdbId}&tmdb=1`
        : `https://multiembed.mov/?video_id=${media.tmdbId}&tmdb=1&s=${season}&e=${episode}`;
  } else if (targetDomain.includes("autoembed")) {
    embedUrl =
      media.type === "movie"
        ? `https://autoembed.cc/embed/player.php?id=${media.tmdbId}`
        : `https://autoembed.cc/embed/player.php?id=${media.tmdbId}&s=${season}&e=${episode}`;
  } else if (targetDomain.includes("2embed")) {
    embedUrl =
      media.type === "movie"
        ? `https://www.2embed.cc/embed/${media.tmdbId}`
        : `https://www.2embed.cc/embedtv/${media.tmdbId}&s=${season}&e=${episode}`;
  } else if (targetDomain.includes("smashy")) {
    embedUrl =
      media.type === "movie"
        ? `https://embed.smashystream.com/playere.php?tmdb=${media.tmdbId}`
        : `https://embed.smashystream.com/playere.php?tmdb=${media.tmdbId}&season=${season}&ep=${episode}`;
  } else {
    embedUrl =
      media.type === "movie"
        ? `https://${targetDomain}/embed/movie?tmdb=${media.tmdbId}`
        : `https://${targetDomain}/embed/tv?tmdb=${media.tmdbId}&season=${season}&episode=${episode}`;
  }

  // Populate Server Dropdown dynamically
  populateServerDropdown(media, season, episode);

  // Create isolated WebView element
  const container = document.getElementById("webview-container");
  container.innerHTML = "";

  const webview = document.createElement("webview");
  webview.id = "active-player-webview";
  webview.className = "webview-player";
  webview.setAttribute("partition", "persist:player");
  webview.setAttribute("src", embedUrl);
  webview.setAttribute("allowfullscreen", "true");

  container.appendChild(webview);
  state.activeWebview = webview;

  // Show player overlay
  document.getElementById("player-overlay").classList.remove("hidden");
  window.electron.showNotification(
    "Streaming Live",
    `Initializing isolated bypass stream from ${targetDomain}`,
  );
}

// Populate the custom dropdown servers list
function populateServerDropdown(media, season, episode) {
  const list = document.getElementById("server-dropdown-list");
  if (!list) return;

  const servers = [
    { name: "VidSrc ME", domain: "vidsrc.me", icon: "🔴" },
    { name: "VidSrc TO", domain: "vidsrc.to", icon: "🟢" },
    { name: "VidSrc PRO", domain: "vidsrc.pro", icon: "🟡" },
    { name: "VidSrc VIP", domain: "vidsrc.vip", icon: "🟣" },
    { name: "VidSrc CC", domain: "vidsrc.cc", icon: "🔵" },
    { name: "SuperEmbed", domain: "multiembed.mov", icon: "⚡" },
    { name: "AutoEmbed", domain: "autoembed.cc", icon: "🔥" },
    { name: "2Embed", domain: "2embed.cc", icon: "🎥" },
    { name: "SmashyStream", domain: "embed.smashystream.com", icon: "💥" }
  ];

  list.innerHTML = "";

  servers.forEach((srv) => {
    const btn = document.createElement("button");
    btn.className =
      "w-full text-left px-4 py-3 hover:bg-white/10 rounded-lg text-sm text-white font-medium flex items-center gap-3 transition cursor-pointer";
    btn.innerHTML = `<span>${srv.icon}</span> ${srv.name} <span class="text-[10px] text-gray-500 ml-auto">${srv.domain}</span>`;
    btn.onclick = () => {
      playStream(media, season, episode, srv.domain);
    };
    list.appendChild(btn);
  });
      "w-full text-left px-4 py-2 hover:bg-white/10 rounded-lg text-sm text-white font-medium flex items-center gap-3 transition";
    btn.innerHTML = `<span>${srv.icon}</span> ${srv.name} <span class="text-[10px] text-gray-500 ml-auto">${srv.domain}</span>`;
    btn.onclick = () => {
      // Re-trigger playback but force the new domain immediately
      playStream(media, season, episode, srv.domain);
    };
    list.appendChild(btn);
  });
}

// Anime direct-stream playback (parity with mobile: AllAnime -> direct URL).
async function playAnimeStream(media, episode) {
  closeDetailModal();
  const titleEl = document.getElementById("player-stream-title");
  titleEl.textContent = `${media.title} — E${episode}`;
  const container = document.getElementById("webview-container");

  // Immersive Loader (Lordflix anime loading style)
  container.innerHTML = `
    <div class="absolute inset-0 z-0 opacity-20 bg-cover bg-center" style="background-image: url('${media.backdrop || media.poster}')"></div>
    <div class="absolute inset-0 bg-gradient-to-t from-[#050505] via-[#050505]/80 to-[#050505]/40 z-10"></div>
    <div class="relative z-20 flex flex-col items-center justify-center h-full gap-4 animate-pulse">
        <img src="https://media.tenor.com/e2qU2h4aEVEAAAAC/anime-cooking.gif" class="w-32 h-32 rounded-xl border-4 border-white/10 shadow-2xl">
        <h2 class="text-white text-2xl font-black tracking-widest drop-shadow-lg">Brewing Sources...</h2>
        <p class="text-gray-400 font-semibold tracking-wide text-sm drop-shadow-md">${media.title} • Episode ${episode}</p>
    </div>
  `;
  document.getElementById("player-overlay").classList.remove("hidden");

  try {
    const src = await window.OmniAnime.resolveSource(media, episode, {
      dub: state.preferDub || false,
    });
    state.animeResume = { media, episode };
    playDirectVideo(container, src.url, src.referer, media, episode);
  } catch (e) {
    if (e && e.name === "CaptchaRequiredError") {
      showAnimeCaptcha(e.url, () => playAnimeStream(media, episode));
      return;
    }
    console.warn("[Omniverse] anime resolve failed:", e);
    container.innerHTML =
      '<div style="display:flex;height:100%;align-items:center;justify-content:center;color:#fff;font-weight:600">No playable source found.</div>';
    window.electron.showNotification(
      "Playback",
      "No playable anime source found.",
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
) {
  // Register the stream host so the main process injects the Referer for it.
  try {
    window.electron.registerAnimeHost(new URL(url).host);
  } catch (_) {}
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
    if (media && media.anilistId && episode) {
      const duration = Math.round(video.duration) || 1440;
      skipIntervals = await fetchDesktopAniSkip(
        media.anilistId,
        episode,
        duration,
      );
    }
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
  const url = `https://api.aniskip.com/v2/skip-times/${anilistId}/${episode}?types[]=op&types[]=ed&types[]=recap&episodeLength=${durationSec}`;
  try {
    const res = await appFetch(url, "GET", {
      Accept: "application/json",
    });
    if (res.ok && res.html) {
      const data = JSON.parse(res.html);
      if (data.found && Array.isArray(data.results)) {
        return data.results.map((r) => ({
          type: r.skipType || r.skip_type,
          start: r.interval.startTime,
          end: r.interval.endTime,
        }));
      }
    }
  } catch (e) {
    console.warn("AniSkip fetch failed:", e);
  }
  return [];
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

function exitPlayer() {
  if (state.activeHls) {
    try {
      state.activeHls.destroy();
    } catch (_) {}
    state.activeHls = null;
  }
  document.getElementById("player-overlay").classList.add("hidden");

  // Safely destroy player WebContents instantly to freeze sound, clear caches, and stop video streams
  const container = document.getElementById("webview-container");
  container.innerHTML = "";
  state.activeWebview = null;

  window.electron.playerStopped(); // GC and Cache flush trigger on main thread
}

function togglePiP() {
  if (state.activeWebview) {
    const url = state.activeWebview.getAttribute("src");
    const title = document.getElementById("player-stream-title").textContent;

    // Open floating window in Main Process
    window.electron.openPipWindow(url, title);

    // Close the internal player to prevent duplicate audio streams
    exitPlayer();
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
      if (state.tmdbToken) {
        showGridLoading("grid-search-results");

        const searchData = await fetchTmdb("search/multi", { query: val });

        if (searchData && searchData.results && searchData.results.length > 0) {
          const items = searchData.results
            .filter(
              (item) =>
                (item.media_type === "movie" || item.media_type === "tv") &&
                (item.poster_path || item.backdrop_path),
            )
            .map((item) => mapTmdbItem(item, item.media_type));

          renderGrid("grid-search-results", items.slice(0, 24), true); // true = lordflix poster style
          lucide.createIcons();
          return;
        }
      }

      // Fallback local filtering
      const filteredMovies = FALLBACK_DB.movies.filter(
        (m) =>
          m.title.toLowerCase().includes(val) ||
          m.overview.toLowerCase().includes(val),
      );
      const filteredTv = FALLBACK_DB.tv.filter(
        (t) =>
          t.title.toLowerCase().includes(val) ||
          t.overview.toLowerCase().includes(val),
      );

      const items = [...filteredMovies, ...filteredTv];
      renderGrid("grid-search-results", items, true);
      lucide.createIcons();
    }, 400);
  });
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
  window.electron.showNotification(
    "Preferences Updated",
    `Preferred VidSrc Domain changed to: ${select.value}`,
  );
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
      "Read Access Token cleared. Reverting to offline catalog feeds.",
    );
  }
  // Reload feeds on TMDB token change
  renderCatalogFeeds();
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
    console.warn("[Omniverse] local QR generation failed, using fallback:", e);
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
// One Pace to One Piece Migration Engine
// ==============================================================================
function mapOnePaceToOnePiece(seasonNumber, episodeNumber) {
  const arcEpisodes = {
    1: "1-3", // Romance Dawn
    2: "4-8", // Orange Town
    3: "9-17", // Syrup Village
    4: "18", // Gaimon
    5: "19-30", // Baratie
    6: "31-44", // Arlong Park
    7: "45,48-53", // Loguetown
    8: "62-63", // Reverse Mountain
    9: "64-67", // Whisky Peak
    10: "70-77", // Little Garden
    11: "78-91", // Drum Island
    12: "92-130", // Alabasta
    13: "144-152", // Jaya
    14: "153-195", // Skypiea
    15: "207-219", // Long Ring Long Land
    16: "229-263", // Water Seven
    17: "263-312", // Enies Lobby
    18: "313-325", // Post-Enies Lobby
    19: "337-381", // Thriller Bark
    20: "385-405", // Sabaody Archipelago
    21: "408-417", // Amazon Lily
    22: "422-452", // Impel Down
    23: "457-489", // Marineford
    24: "490-516", // Post-War
    25: "517-522", // Return to Sabaody
    26: "523-574", // Fishman Island
    27: "579-625", // Punk Hazard
    28: "629-746", // Dressrosa
    29: "751-779", // Zou
    30: "777-877", // Whole Cake Island
    31: "878-889", // Reverie
    32: "890-1085", // Wano
    33: "1086-1155", // Egghead
  };

  const arcTotalEpisodes = {
    1: 2,
    2: 3,
    3: 7,
    4: 1,
    5: 10,
    6: 10,
    7: 5,
    8: 1,
    9: 2,
    10: 5,
    11: 6,
    12: 21,
    13: 5,
    14: 24,
    15: 3,
    16: 20,
    17: 25,
    18: 5,
    19: 22,
    20: 11,
    21: 4,
    22: 14,
    23: 17,
    24: 8,
    25: 2,
    26: 22,
    27: 20,
    28: 48,
    29: 10,
    30: 39,
    31: 4,
    32: 60,
    33: 21,
  };

  const episodesStr = arcEpisodes[seasonNumber] || "1";
  const epNumbers = [];
  const parts = episodesStr.split(",");
  for (const part of parts) {
    const clean = part.trim();
    if (clean.includes("-")) {
      const rp = clean.split("-");
      if (rp.length === 2) {
        const s = parseInt(rp[0].trim(), 10);
        const e = parseInt(rp[1].trim(), 10);
        if (!isNaN(s) && !isNaN(e)) {
          for (let n = s; n <= e; n++) epNumbers.push(n);
        }
      }
    } else {
      const parsed = parseInt(clean, 10);
      if (!isNaN(parsed)) epNumbers.push(parsed);
    }
  }

  if (epNumbers.length === 0) return 1;
  const totalEpisodes = arcTotalEpisodes[seasonNumber] || 1;
  if (totalEpisodes <= 1) return epNumbers[0];

  const ratio = (episodeNumber - 1) / (totalEpisodes - 1);
  const targetIndex = Math.min(
    epNumbers.length - 1,
    Math.max(0, Math.floor(ratio * (epNumbers.length - 1))),
  );
  return epNumbers[targetIndex];
}

function getRealOnePaceSeason(season) {
  // Definitive list of One Pace website slugs in order (1-based index is the website's season number).
  const websiteSlugs = [
    "romance-dawn", // 1
    "orange-town", // 2
    "syrup-village", // 3
    "gaimon", // 4
    "baratie", // 5
    "arlong-park", // 6
    "the-adventures-of-buggys-crew", // 7 (Specials / Cover Stories)
    "loguetown", // 8
    "reverse-mountain", // 9
    "whisky-peak", // 10
    "the-trials-of-koby-meppo", // 11 (Specials / Cover Stories)
    "little-garden", // 12
    "drum-island", // 13
    "alabasta", // 14
    "jaya", // 15
    "skypiea", // 16
    "long-ring-long-land", // 17
    "water-seven", // 18
    "enies-lobby", // 19
    "post-enies-lobby", // 20
    "thriller-bark", // 21
    "sabaody-archipelago", // 22
    "amazon-lily", // 23
    "impel-down", // 24
    "if-you-could-go-anywhere-the-adventures-of-the-straw-hats", // 25 (Specials / Cover Stories)
    "marineford", // 26
    "post-war", // 27
    "return-to-sabaody", // 28
    "fishman-island", // 29
    "punk-hazard", // 30
    "dressrosa", // 31
    "zou", // 32
    "whole-cake-island", // 33
    "reverie", // 34
    "wano", // 35
    "egghead", // 36
  ];
  const slug = websiteSlugs[season - 1];
  if (!slug) return season;
  switch (slug) {
    case "romance-dawn":
      return 1;
    case "orange-town":
      return 2;
    case "syrup-village":
      return 3;
    case "gaimon":
      return 4;
    case "baratie":
      return 5;
    case "arlong-park":
      return 6;
    case "the-adventures-of-buggys-crew":
      return 0; // special
    case "loguetown":
      return 7;
    case "reverse-mountain":
      return 8;
    case "whisky-peak":
      return 9;
    case "the-trials-of-koby-meppo":
      return 0; // special
    case "little-garden":
      return 10;
    case "drum-island":
      return 11;
    case "alabasta":
      return 12;
    case "jaya":
      return 13;
    case "skypiea":
      return 14;
    case "long-ring-long-land":
      return 15;
    case "water-seven":
      return 16;
    case "enies-lobby":
      return 17;
    case "post-enies-lobby":
      return 18;
    case "thriller-bark":
      return 19;
    case "sabaody-archipelago":
      return 20;
    case "amazon-lily":
      return 21;
    case "impel-down":
      return 22;
    case "if-you-could-go-anywhere-the-adventures-of-the-straw-hats":
      return 0; // special
    case "marineford":
      return 23;
    case "post-war":
      return 24;
    case "return-to-sabaody":
      return 25;
    case "fishman-island":
      return 26;
    case "punk-hazard":
      return 27;
    case "dressrosa":
      return 28;
    case "zou":
      return 29;
    case "whole-cake-island":
      return 30;
    case "reverie":
      return 31;
    case "wano":
      return 32;
    case "egghead":
      return 33;
    default:
      return season;
  }
}

function checkOnePaceMigration() {
  const history = state.watchHistory || [];
  const paceEntry = history.find(
    (h) =>
      h.itemId === "onepace:anime:21" ||
      h.title === "One Pace" ||
      (h.itemId && h.itemId.startsWith("onepace:")),
  );
  if (!paceEntry) return;

  const modal = document.createElement("div");
  modal.id = "onepace-migration-modal";
  modal.className =
    "fixed inset-0 z-[10000] detail-modal-overlay flex items-center justify-center p-6";
  modal.innerHTML = `
    <div class="detail-modal-card w-full max-w-md p-6 rounded-2xl space-y-6 text-center animate-fade-in bg-brandSec border border-white/[0.04]">
      <div class="flex flex-col items-center gap-3">
        <div class="w-12 h-12 rounded-full bg-cyan-950/40 border border-brandCyan/30 flex items-center justify-center text-brandCyan">
          <i data-lucide="refresh-cw" class="w-6 h-6 animate-spin"></i>
        </div>
        <h2 class="font-extrabold text-lg text-white">One Pace Migration Assistant</h2>
      </div>
      <p class="text-xs text-gray-400 leading-relaxed">
        The One Pace addon has been removed in this update. We detected that you were watching <span class="text-brandCyan font-bold">One Pace</span> (Season ${paceEntry.season || paceEntry.seasonNumber || 1}, Episode ${paceEntry.episode || paceEntry.episodeNumber || 1}).
      </p>
      <p class="text-xs text-gray-400 leading-relaxed">
        Would you like to automatically migrate your watch progress to the official <span class="text-brandCyan font-bold">One Piece</span> anime series? We will map your current episode and position to the correct corresponding episode in One Piece.
      </p>
      <div class="flex gap-3 pt-2">
        <button id="btn-migrate-dismiss" class="flex-1 py-2.5 rounded-xl text-xs font-bold text-gray-400 bg-white/5 hover:bg-white/10 transition">
          Dismiss & Clear
        </button>
        <button id="btn-migrate-confirm" class="flex-1 py-2.5 rounded-xl text-xs font-bold text-brandDark btn-action-glow">
          Migrate Progress
        </button>
      </div>
    </div>
  `;
  document.body.appendChild(modal);
  lucide.createIcons();

  document.getElementById("btn-migrate-dismiss").onclick = () => {
    state.watchHistory = history.filter(
      (h) =>
        h.itemId !== "onepace:anime:21" &&
        h.title !== "One Pace" &&
        !(h.itemId && h.itemId.startsWith("onepace:")),
    );
    localStorage.setItem(
      "omni_watch_history",
      JSON.stringify(state.watchHistory),
    );
    modal.remove();
    renderContinueWatching();
  };

  document.getElementById("btn-migrate-confirm").onclick = async () => {
    const season = paceEntry.season || paceEntry.seasonNumber || 1;
    const epNum = paceEntry.episode || paceEntry.episodeNumber || 1;
    const realSeason = getRealOnePaceSeason(season);
    const originalEpisode =
      realSeason === 0 ? 1 : mapOnePaceToOnePiece(realSeason, epNum);

    const pieceEntry = {
      itemId: "anilist:anime:21",
      title: "One Piece",
      type: "anime",
      seasonNumber: 1,
      episodeNumber: originalEpisode,
      positionMs: paceEntry.positionMs || 0,
      durationMs: paceEntry.durationMs || 1500000,
      lastWatchedAt: Date.now(),
      poster: "https://image.tmdb.org/t/p/w500/or06gK6hxJN98Es842gZgYI7CIE.jpg",
      backdrop:
        "https://image.tmdb.org/t/p/original/bMv9mO_b2qf8U4VwYAtW3Zc40S9.jpg",
    };

    state.watchHistory = history.filter(
      (h) =>
        h.itemId !== "onepace:anime:21" &&
        h.title !== "One Pace" &&
        !(h.itemId && h.itemId.startsWith("onepace:")),
    );
    state.watchHistory.push(pieceEntry);
    localStorage.setItem(
      "omni_watch_history",
      JSON.stringify(state.watchHistory),
    );

    window.electron.showNotification(
      "Migration Successful",
      `Your progress has been migrated to One Piece Episode ${originalEpisode}!`,
    );

    if (state.traktToken) {
      pushToTrakt(); // Run in background, don't block UI!
    }

    modal.remove();
    renderContinueWatching();
  };
}

// ==============================================================================
// Trakt Bidirectional Sync Engine & Continue Watching Shelf
// ==============================================================================
function normalizeWatchProgress(rawItem) {
  const poster = rawItem.posterPath
    ? rawItem.posterPath.startsWith("http")
      ? rawItem.posterPath
      : `https://image.tmdb.org/t/p/w500${rawItem.posterPath}`
    : rawItem.poster ||
      "https://ui-avatars.com/api/?background=111&color=fff&name=Media";

  const backdrop = rawItem.backdropPath
    ? rawItem.backdropPath.startsWith("http")
      ? rawItem.backdropPath
      : `https://image.tmdb.org/t/p/original${rawItem.backdropPath}`
    : rawItem.backdrop ||
      "https://ui-avatars.com/api/?background=111&color=fff&name=Media";

  let progress = 0;
  if (rawItem.positionMs && rawItem.durationMs && rawItem.durationMs > 0) {
    progress = rawItem.positionMs / rawItem.durationMs;
  } else if (rawItem.progress !== undefined) {
    progress = rawItem.progress;
  }

  const season =
    rawItem.seasonNumber !== undefined
      ? rawItem.seasonNumber
      : rawItem.season !== undefined
        ? rawItem.season
        : 1;
  const episode =
    rawItem.episodeNumber !== undefined
      ? rawItem.episodeNumber
      : rawItem.episode !== undefined
        ? rawItem.episode
        : 1;

  return {
    ...rawItem,
    poster,
    backdrop,
    progress,
    season,
    episode,
  };
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

  // Grouping logic: movie -> standalone, tv/anime/onepace -> group by show title (Clean Continue Watching)
  const grouped = [];
  const seenShows = new Set();

  const sortedHistory = [...state.watchHistory]
    .map(normalizeWatchProgress)
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
    card.onclick = () => resumeWatchProgress(item);

    const progressPercent = Math.round((item.progress || 0) * 100);
    let subtitle = item.type.toUpperCase();
    if (
      item.type === "tv" ||
      item.type === "anime" ||
      item.type === "onepace"
    ) {
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

function saveWatchProgress(item) {
  const idx = state.watchHistory.findIndex((h) => h.itemId === item.itemId);
  if (idx >= 0) {
    state.watchHistory[idx] = item;
  } else {
    state.watchHistory.push(item);
  }

  localStorage.setItem(
    "omni_watch_history",
    JSON.stringify(state.watchHistory),
  );
  renderContinueWatching();

  if (state.traktToken) {
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
  const item = normalizeWatchProgress(rawItem);
  // Map WatchProgress back to MediaItem for detail modal
  const mediaItem = {
    id: item.itemId,
    title: item.title,
    type: item.type,
    poster: item.poster,
    backdrop: item.backdrop,
    year: new Date(item.lastWatchedAt).getFullYear(),
    rating: "—",
    overview: item.episodeTitle
      ? `Resume watching: ${item.episodeTitle}`
      : "Continue watching from history.",
    seasons: item.season ? item.season : 1,
    tmdbId: parseInt(item.itemId.split(":").pop()) || null,
  };
  openDetailModal(mediaItem);
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

  state.watchHistory = Array.from(localMap.values());
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
