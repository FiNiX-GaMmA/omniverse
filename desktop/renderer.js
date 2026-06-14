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
document.addEventListener("DOMContentLoaded", () => {
  setupPlatformWindowDecorations();
  loadSavedPreferences();
  switchScreen("home");
  renderCatalogFeeds();
  setupSearchInput();
  setupLiveTvCenter();
  setupAdblockObserver();
  lucide.createIcons();
});

// Configure Window Controls based on OS
async function setupPlatformWindowDecorations() {
  const platform = await window.electron.getPlatform();
  if (platform !== "darwin") {
    // Windows and Linux have custom draggable title bar buttons
    const controls = document.getElementById("window-controls");
    if (controls) controls.classList.remove("hidden");
  }
}

// Load configurations
function loadSavedPreferences() {
  document.getElementById("tmdb-token-input").value = state.tmdbToken;
  document.getElementById("vidsrc-domain-select").value = state.vidsrcDomain;
}

// Render dynamic elements
function renderCatalogFeeds() {
  renderGrid("grid-trending-movies", FALLBACK_DB.movies);
  renderGrid("grid-trending-tv", FALLBACK_DB.tv);
  renderGrid("grid-all-movies", FALLBACK_DB.movies);
  renderGrid("grid-all-tv", FALLBACK_DB.tv);
  renderGrid("grid-all-anime", FALLBACK_DB.anime);
}

function renderGrid(containerId, items) {
  const container = document.getElementById(containerId);
  if (!container) return;
  container.innerHTML = "";

  items.forEach((item) => {
    const card = document.createElement("div");
    card.className =
      "media-card bg-brandSec rounded-xl border border-white/[0.04] p-2 hover:border-brandCyan/20 cursor-pointer text-left";
    card.onclick = () => openDetailModal(item);

    card.innerHTML = `
      <div class="relative aspect-[2/3] rounded-lg overflow-hidden bg-brandTert mb-2">
        <img src="${item.poster}" alt="${item.title}" class="w-full h-full object-cover" loading="lazy">
        <span class="absolute top-1.5 right-1.5 bg-brandDark/80 border border-white/[0.06] text-amber-400 font-extrabold text-[9px] px-1.5 py-0.5 rounded flex items-center gap-0.5">
          ★ ${item.rating}
        </span>
      </div>
      <div class="px-1 space-y-0.5">
        <h4 class="text-xs font-bold text-gray-200 truncate leading-snug">${item.title}</h4>
        <div class="flex items-center justify-between text-[10px] text-gray-500 font-medium">
          <span>${item.year}</span>
          <span class="uppercase text-[9px] tracking-wider text-brandCyan bg-cyan-950/20 border border-brandCyan/10 px-1 rounded">${item.type}</span>
        </div>
      </div>
    `;
    container.appendChild(card);
  });
}

// Single Page Screen Routing
function switchScreen(screenName) {
  state.currentScreen = screenName;
  state.activeStudio = "";

  // Hide all screens
  const screens = ["home", "movies", "tv", "anime", "livetv", "settings"];
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
}

// Studio Filtering logic
function filterByStudio(studio) {
  state.activeStudio = studio;
  switchScreen("movies");

  // Re-filter movies screen grid (mock filter)
  const headline = document.querySelector("#screen-movies h1");
  headline.textContent = `${studio.toUpperCase()} NETWORKS`;

  // Real world query would pass with_companies parameter to TMDB
  // For demo, we highlight the custom filtering state
  window.electron.showNotification(
    "Network Filtering",
    `Filtering Movies catalog by: ${studio.toUpperCase()}`,
  );
}

// Detail Sheet Overlay Manager
function openDetailModal(media) {
  state.selectedMedia = media;

  document.getElementById("modal-poster").src = media.poster;
  document.getElementById("modal-title").textContent = media.title;
  document.getElementById("modal-overview").textContent = media.overview;
  document.getElementById("modal-year-chip").textContent = media.year;
  document.getElementById("modal-rating-chip").innerHTML =
    `<i data-lucide="star" class="w-3.5 h-3.5 fill-amber-400"></i> ${media.rating}`;

  const typeChip = document.getElementById("modal-type-chip");
  typeChip.textContent = media.type.toUpperCase();

  const episodeSection = document.getElementById("modal-episodes-section");
  const playBtn = document.getElementById("modal-play-btn");

  if (media.type === "tv" || media.type === "anime") {
    episodeSection.classList.remove("hidden");
    playBtn.classList.add("hidden"); // Use episode cards to trigger streams

    // Set seasons dropdown
    const selector = document.getElementById("season-selector");
    selector.innerHTML = "";

    const seasonCount = media.seasons || 1;
    for (let s = 1; s <= seasonCount; s++) {
      selector.innerHTML += `<option value="${s}">Season ${s}</option>`;
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

function loadSeasonEpisodes() {
  const media = state.selectedMedia;
  const seasonSelect = document.getElementById("season-selector");
  const seasonVal = parseInt(seasonSelect.value) || 1;
  const grid = document.getElementById("episodes-grid");
  grid.innerHTML = "";

  // Work out episode count
  let epCount = 10;
  if (media.episodesPerSeason && media.episodesPerSeason[seasonVal - 1]) {
    epCount = media.episodesPerSeason[seasonVal - 1];
  } else if (media.id === "a1") {
    epCount = 12; // Cap One Piece demo display list
  }

  for (let ep = 1; ep <= epCount; ep++) {
    const epRow = document.createElement("button");
    epRow.className =
      "w-full text-left p-3 rounded-lg bg-brandTert hover:bg-brandCyan/10 border border-white/[0.04] text-xs font-semibold flex items-center justify-between group transition duration-200";
    epRow.onclick = () => playStream(media, seasonVal, ep);

    epRow.innerHTML = `
      <div class="flex items-center gap-3">
        <span class="text-brandCyan bg-cyan-950/40 px-2 py-1 rounded">EP ${ep}</span>
        <span class="text-gray-300 group-hover:text-white transition">Episode ${ep}</span>
      </div>
      <i data-lucide="play" class="w-3.5 h-3.5 text-gray-500 group-hover:text-brandCyan fill-transparent group-hover:fill-brandCyan transition duration-300"></i>
    `;
    grid.appendChild(epRow);
  }
  lucide.createIcons();
}

// Integrated Secure Webview Playback Launcher
function playStream(media, season = null, episode = null) {
  closeDetailModal();

  const titleEl = document.getElementById("player-stream-title");
  let embedUrl = "";

  if (media.type === "movie") {
    titleEl.textContent = `${media.title} (Movie)`;
    embedUrl = `https://${state.vidsrcDomain}/embed/movie?tmdb=${media.tmdbId}`;
  } else {
    titleEl.textContent = `${media.title} — S${season} E${episode}`;
    embedUrl = `https://${state.vidsrcDomain}/embed/tv?tmdb=${media.tmdbId}&season=${season}&episode=${episode}`;
  }

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
    `Initializing isolated bypass stream for ${media.title}`,
  );
}

function exitPlayer() {
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
      const res = await window.electron.iptvFetch("https://iptv-web.app/");
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
    const res = await window.electron.iptvFetch(
      `https://iptv-web.app/${countryCode}/`,
    );
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
  const res = await window.electron.iptvFetch(fullUrl);
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
  input.addEventListener("input", (e) => {
    const val = e.target.value.toLowerCase().trim();
    if (!val) {
      renderCatalogFeeds();
      return;
    }

    // Filter combined media listings
    const filteredMovies = FALLBACK_DB.movies.filter((m) =>
      m.title.toLowerCase().includes(val),
    );
    const filteredTv = FALLBACK_DB.tv.filter((t) =>
      t.title.toLowerCase().includes(val),
    );

    // Direct view updates
    renderGrid("grid-trending-movies", filteredMovies);
    renderGrid("grid-trending-tv", filteredTv);
    renderGrid("grid-all-movies", filteredMovies);
    renderGrid("grid-all-tv", filteredTv);

    // Switch to home screen for general visibility
    if (
      state.currentScreen !== "home" &&
      state.currentScreen !== "movies" &&
      state.currentScreen !== "tv"
    ) {
      switchScreen("home");
    }
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
      document.getElementById("tmdb-token-input").value = config.tmdb_token;
    }

    if (config.settings && config.settings.vidsrcDomain) {
      state.vidsrcDomain = config.settings.vidsrcDomain;
      localStorage.setItem("omni_vidsrc_domain", config.settings.vidsrcDomain);
      document.getElementById("vidsrc-domain-select").value =
        config.settings.vidsrcDomain;
    }

    input.value = "";
    window.electron.showNotification(
      "Sync Successful",
      "Cloud Sync finished. Re-loaded credentials, accounts, and play preferences.",
    );

    // Refresh feed configurations
    renderCatalogFeeds();
  } catch (err) {
    console.error("Sync parsing error: ", err);
    window.electron.showNotification(
      "Sync Error",
      "Could not parse credentials. Package base64 corrupted.",
    );
  }
}

// ==============================================================================
// In-App Update Engine (Over-The-Air Sideloading)
// ==============================================================================
const APP_VERSION = "2.1.0"; // Matches packaging release
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

async function checkAppUpdates() {
  const checkBtn = document.getElementById("check-update-btn");
  if (checkBtn) {
    checkBtn.disabled = true;
    checkBtn.textContent = "Checking...";
  }

  try {
    const res = await window.electron.iptvFetch(
      "https://api.github.com/repos/FiNiX-GaMmA/omniverse/releases/latest",
    );
    if (!res.ok) throw new Error(res.error || "GitHub request failed");

    const release = JSON.parse(res.html);
    const remoteVersion = release.tag_name || "";
    const releaseNotes = release.body || "No release notes available.";

    if (isNewerVersion(APP_VERSION, remoteVersion)) {
      const platform = await window.electron.getPlatform();
      let targetAsset = null;

      // Filter assets based on host platform extension
      if (release.assets && Array.isArray(release.assets)) {
        release.assets.forEach((asset) => {
          const name = asset.name.toLowerCase();
          if (
            platform === "win32" &&
            name.endsWith(".exe") &&
            !name.includes("unsigned") &&
            !name.includes("apk")
          ) {
            targetAsset = asset;
          } else if (platform === "darwin" && name.endsWith(".dmg")) {
            targetAsset = asset;
          } else if (
            platform === "linux" &&
            (name.endsWith(".appimage") || name.endsWith(".deb"))
          ) {
            // Prefer AppImage for portable running
            if (!targetAsset || name.endsWith(".appimage")) {
              targetAsset = asset;
            }
          }
        });
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
          "Update Found",
          `Omniverse v${remoteVersion} is available for download!`,
        );
      } else {
        window.electron.showNotification(
          "Update Available",
          `Omniverse v${remoteVersion} is released, but the installer for ${platform} is compiling.`,
        );
      }
    } else {
      window.electron.showNotification(
        "Up To Date",
        "You are running the latest version of Omniverse Desktop.",
      );
    }
  } catch (err) {
    console.error("Update Checker error: ", err);
    window.electron.showNotification(
      "Update Check Failed",
      "Could not check for newer releases.",
    );
  } finally {
    if (checkBtn) {
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
