// ==============================================================================
// Omniverse Desktop — Anime pipeline (faithful port of the mobile AnimeRepository)
// ==============================================================================
// Mirrors android/.../AnimeRepositoryImpl.kt and ios/.../AnimeRepository.swift:
// AniList (metadata/discovery) + AllAnime / AllManga (playback), the same path
// ani-cli uses. The AllAnime episode payload ("tobeparsed") is AES-256-CTR
// encrypted and source URLs are hex-encoded; both are decoded here with WebCrypto.
//
// Networking goes through window.electron.iptvFetch (main-process fetch) to avoid
// renderer CORS. Exposes window.OmniAnime.
//
// NOTE: the HiAnime/Megacloud fallback is not ported here yet (documented TODO);
// AllAnime + the captcha flow is the primary path and covers the captcha case.
// ==============================================================================

(function () {
  const ANILIST = "https://graphql.anilist.co";
  const ALLANIME = "https://api.allanime.day/api";
  const CAPTCHA_URL = "https://allmanga.to"; // tune if the solvable host differs

  const SEARCH_GQL =
    "query($search:SearchInput $limit:Int $page:Int $translationType:VaildTranslationTypeEnumType $countryOrigin:VaildCountryOriginEnumType){shows(search:$search limit:$limit page:$page translationType:$translationType countryOrigin:$countryOrigin){edges{_id name availableEpisodes __typename}}}";
  const EPISODE_GQL =
    "query($showId:String! $translationType:VaildTranslationTypeEnumType! $episodeString:String!){episode(showId:$showId translationType:$translationType episodeString:$episodeString){episodeString sourceUrls}}";
  const EPISODE_GQL_HASH =
    "d405d0edd690624b66baba3068e0edc3ac90f1597d898a1ec8db4e5c43c00fec";
  const PROVIDER_PRIORITY = ["S-mp4", "Luf-Mp4", "Yt-mp4", "Default", "Sl-Hls"];

  const ALLANIME_HEADERS = {
    Referer: "https://allmanga.to",
    Origin: "https://allmanga.to",
    Accept: "*/*",
  };
  const ALLMANGA_HEADERS = { Referer: "https://allmanga.to", Accept: "*/*" };

  // Raised by resolveSource when AllAnime answers NEED_CAPTCHA.
  class CaptchaRequiredError extends Error {
    constructor(url) {
      super("AllAnime needs a captcha solved before it will hand over sources.");
      this.name = "CaptchaRequiredError";
      this.url = url;
    }
  }

  // MARK: - HTTP helpers (via main-process fetch, no CORS)

  async function httpText(url, { method = "GET", headers = {}, body = null } = {}) {
    const res = await window.electron.iptvFetch(url, method, headers, body);
    if (!res || res.ok === false) {
      return { ok: false, status: res && res.status ? res.status : 0, body: "" };
    }
    return { ok: true, status: res.status || 200, body: res.html || "" };
  }

  async function postJson(url, obj, headers = {}) {
    const res = await httpText(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", ...headers },
      body: JSON.stringify(obj),
    });
    try {
      return JSON.parse(res.body || "{}");
    } catch {
      return {};
    }
  }

  // MARK: - Discovery (AniList) — mirrors fetchAnimeCategories

  function currentAnilistSeason() {
    const d = new Date();
    const m = d.getMonth() + 1;
    const year = d.getFullYear();
    let season = "FALL";
    if (m <= 3) season = "WINTER";
    else if (m <= 6) season = "SPRING";
    else if (m <= 9) season = "SUMMER";
    const label = season[0] + season.slice(1).toLowerCase();
    return { season, label, year };
  }

  function cleanDescription(v) {
    return (v || "")
      .replace(/<[^>]*>/g, "")
      .replace(/\(Source:[^)]*\)/gi, "")
      .replace(/\bNote:[^\n]*/gi, "")
      .trim();
  }

  function mediaFromAnilist(json) {
    const id = json.id || 0;
    const t = json.title || {};
    const title = t.english || t.romaji || t.native || "Anime";
    const format = json.format || null;
    const episodes =
      json.episodes != null ? json.episodes : format === "MOVIE" ? 1 : 0;
    const year =
      json.seasonYear != null
        ? json.seasonYear
        : json.startDate && json.startDate.year != null
        ? json.startDate.year
        : null;
    const cover = json.coverImage || {};
    const studiosArr = (json.studios && json.studios.nodes) || [];
    const studios = studiosArr
      .map((s) => s && s.name)
      .filter(Boolean)
      .slice(0, 3);
    return {
      id: "anilist:anime:" + id,
      anilistId: id,
      type: "anime",
      title,
      overview: cleanDescription(json.description || ""),
      poster: cover.extraLarge || cover.large || "",
      backdrop: json.bannerImage || "",
      year: year != null ? String(year) : "",
      rating: ((json.averageScore != null ? json.averageScore : 0) / 10).toFixed(1),
      genres: json.genres || [],
      directors: studios,
      runtimeMinutes: json.duration != null ? json.duration : null,
      episodesTotal: episodes,
      seasons: 1,
      source: "anilist",
    };
  }

  const ANIME_FIELDS = `
fragment animeFields on Media {
  id
  title { romaji english native }
  description(asHtml: false)
  coverImage { extraLarge large }
  bannerImage
  genres
  averageScore
  episodes
  duration
  format
  seasonYear
  startDate { year month day }
  studios(isMain: true) { nodes { name } }
}`;

  async function fetchAnimeCategories() {
    const s = currentAnilistSeason();
    const specs = [
      { id: "anime_trending", title: "Trending Now", sort: ["TRENDING_DESC"] },
      { id: "anime_airing", title: "Currently Airing", sort: ["POPULARITY_DESC"], status: "RELEASING" },
      { id: "anime_this_season", title: `${s.label} ${s.year}`, sort: ["POPULARITY_DESC"], season: s.season, seasonYear: s.year },
      { id: "anime_top_rated", title: "All-Time Top Rated", sort: ["SCORE_DESC"] },
      { id: "anime_popular", title: "All-Time Popular", sort: ["POPULARITY_DESC"] },
      { id: "anime_recent", title: "Recently Added", sort: ["ID_DESC"] },
      { id: "anime_movies", title: "Anime Movies", sort: ["SCORE_DESC"], format: "MOVIE" },
      { id: "anime_action", title: "Action", sort: ["POPULARITY_DESC"], genre: "Action" },
      { id: "anime_romance", title: "Romance", sort: ["POPULARITY_DESC"], genre: "Romance" },
      { id: "anime_fantasy", title: "Fantasy", sort: ["POPULARITY_DESC"], genre: "Fantasy" },
    ];

    let aliasBlocks = "";
    specs.forEach((c, i) => {
      const args = ["type: ANIME", `sort: [${c.sort.join(", ")}]`];
      if (c.format) args.push(`format: ${c.format}`);
      if (c.status) args.push(`status: ${c.status}`);
      if (c.season) args.push(`season: ${c.season}`);
      if (c.seasonYear) args.push(`seasonYear: ${c.seasonYear}`);
      if (c.genre) args.push(`genre: "${c.genre}"`);
      args.push("isAdult: false");
      aliasBlocks += `  r${i}: Page(page: 1, perPage: 24) { media(${args.join(", ")}) { ...animeFields } }\n`;
    });
    const query = `${ANIME_FIELDS}\nquery {\n${aliasBlocks}}\n`;

    try {
      const body = await postJson(ANILIST, { query });
      const data = (body && body.data) || {};
      return specs.map((c, i) => {
        const media = data[`r${i}`] && data[`r${i}`].media;
        const items = Array.isArray(media) ? media.map(mediaFromAnilist) : [];
        return { id: c.id, title: c.title, type: "anime", items };
      });
    } catch {
      return specs.map((c) => ({ id: c.id, title: c.title, type: "anime", items: [] }));
    }
  }

  async function findByTitle(title) {
    const q = (title || "").trim();
    if (!q) return null;
    const gql = `query($search: String) { Page(page: 1, perPage: 5) { media(type: ANIME, search: $search, sort: [SEARCH_MATCH, POPULARITY_DESC], isAdult: false) { id title { romaji english native } description(asHtml: false) coverImage { extraLarge large } bannerImage genres averageScore episodes duration format seasonYear startDate { year } studios(isMain: true) { nodes { name } } } } }`;
    try {
      const body = await postJson(ANILIST, { query: gql, variables: { search: q } });
      const media = body && body.data && body.data.Page && body.data.Page.media;
      if (!media || !media.length) return null;
      return mediaFromAnilist(media[0]);
    } catch {
      return null;
    }
  }

  // MARK: - Episodes — mirrors fetchEpisodes

  async function anilistEpisodeMeta(title) {
    const gql = `query($search: String) { Media(type: ANIME, search: $search, sort: SEARCH_MATCH) { streamingEpisodes { title thumbnail } } }`;
    try {
      const body = await postJson(ANILIST, { query: gql, variables: { search: title } });
      const eps =
        body && body.data && body.data.Media && body.data.Media.streamingEpisodes;
      if (!Array.isArray(eps)) return {};
      const out = {};
      const pattern = /^(?:Episode\s+)?(\d+)\s*[-:.|]\s*(.+)$/i;
      eps.forEach((e, i) => {
        const raw = (e.title || "").trim();
        const thumb = (e.thumbnail || "").trim();
        let number = i + 1;
        let text = raw;
        const m = pattern.exec(raw);
        if (m) {
          const n = parseInt(m[1], 10);
          if (!Number.isNaN(n) && m[2]) {
            number = n;
            text = m[2].trim();
          }
        }
        out[number] = { title: text, thumbnail: thumb || null };
      });
      return out;
    } catch {
      return {};
    }
  }

  /** Picks the best AllAnime show for a query — exact name, else max episodes,
   * dropping "one pace" fan-cuts. Mirrors bestAllmangaMatch. */
  function bestAllmangaMatch(edges, query) {
    if (!edges || !edges.length) return null;
    const lower = (query || "").toLowerCase().trim();
    const queryIsOnePace = lower.includes("one pace");
    let candidates = edges.filter((e) => {
      const name = ((e.name || "") + "").toLowerCase().trim();
      return queryIsOnePace || !name.includes("one pace");
    });
    if (!candidates.length) candidates = edges;

    const exact = candidates.find(
      (e) => ((e.name || "") + "").toLowerCase().trim() === lower
    );
    if (exact) return exact;

    let best = null;
    let bestCount = -1;
    for (const e of candidates) {
      const av = e.availableEpisodes || {};
      const c = Math.max(av.sub || 0, av.dub || 0, av.raw || 0);
      if (c > bestCount) {
        bestCount = c;
        best = e;
      }
    }
    return best;
  }

  async function searchAllmanga(query, translationType) {
    const variables = {
      search: { allowAdult: false, allowUnknown: false, query: (query || "").toLowerCase() },
      limit: 40,
      page: 1,
      translationType,
      countryOrigin: "ALL",
    };
    const body = await postJson(ALLANIME, { variables, query: SEARCH_GQL }, ALLANIME_HEADERS);
    const edges = body && body.data && body.data.shows && body.data.shows.edges;
    return Array.isArray(edges) ? edges : null;
  }

  async function allmangaEpisodeCount(title) {
    try {
      const edges = await searchAllmanga(title, "sub");
      if (!edges || !edges.length) return null;
      const entry = bestAllmangaMatch(edges, title);
      if (!entry) return null;
      const av = entry.availableEpisodes || {};
      const max = Math.max(av.sub || 0, av.dub || 0, av.raw || 0);
      return max === 0 ? null : max;
    } catch {
      return null;
    }
  }

  /** Returns { count, meta } for an anime item's season. */
  async function fetchEpisodes(item, seasonNumber = 1) {
    const searchTitle = item.title;
    const live = await allmangaEpisodeCount(searchTitle);
    const planned = item.episodesTotal || 0;
    const count = live != null ? live : planned;
    if (count <= 0) return { count: 0, meta: {} };
    const meta = await anilistEpisodeMeta(searchTitle);
    return { count, meta };
  }

  // MARK: - Source resolution — mirrors resolveAllmanga / resolveSource

  let episodeNeededCaptcha = false;

  async function sha256Bytes(str) {
    const data = new TextEncoder().encode(str);
    const digest = await crypto.subtle.digest("SHA-256", data);
    return new Uint8Array(digest);
  }

  function b64ToBytes(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  // AES-256-CTR decode of the "tobeparsed" blob. Mirrors decodeTobeparsed.
  async function decodeTobeparsed(blob) {
    try {
      const bytes = b64ToBytes(blob);
      if (bytes.length <= 29) return [];
      const key = await sha256Bytes("Xot36i3lK3:v1");
      const iv = new Uint8Array(16);
      iv.set(bytes.slice(1, 13), 0);
      iv.set([0, 0, 0, 2], 12);
      const ciphertext = bytes.slice(13, bytes.length - 16);
      const cryptoKey = await crypto.subtle.importKey("raw", key, { name: "AES-CTR" }, false, ["decrypt"]);
      const plainBuf = await crypto.subtle.decrypt(
        { name: "AES-CTR", counter: iv, length: 128 },
        cryptoKey,
        ciphertext
      );
      const plain = new TextDecoder().decode(plainBuf);
      const sources = [];
      for (const chunk of plain.split(/[{}]/)) {
        const url = /"sourceUrl"\s*:\s*"(--[^"]+)"/.exec(chunk);
        if (!url) continue;
        const name = /"sourceName"\s*:\s*"([^"]+)"/.exec(chunk);
        const priority = /"priority"\s*:\s*([0-9.]+)/.exec(chunk);
        sources.push({
          sourceUrl: url[1],
          sourceName: name ? name[1] : "",
          priority: priority ? parseFloat(priority[1]) : 0,
        });
      }
      return sources;
    } catch {
      return [];
    }
  }

  const HEX_MAP = {
    "79": "A", "7a": "B", "7b": "C", "7c": "D", "7d": "E", "7e": "F", "7f": "G",
    "70": "H", "71": "I", "72": "J", "73": "K", "74": "L", "75": "M", "76": "N",
    "77": "O", "68": "P", "69": "Q", "6a": "R", "6b": "S", "6c": "T", "6d": "U",
    "6e": "V", "6f": "W", "60": "X", "61": "Y", "62": "Z", "59": "a", "5a": "b",
    "5b": "c", "5c": "d", "5d": "e", "5e": "f", "5f": "g", "50": "h", "51": "i",
    "52": "j", "53": "k", "54": "l", "55": "m", "56": "n", "57": "o", "48": "p",
    "49": "q", "4a": "r", "4b": "s", "4c": "t", "4d": "u", "4e": "v", "4f": "w",
    "40": "x", "41": "y", "42": "z", "08": "0", "09": "1", "0a": "2", "0b": "3",
    "0c": "4", "0d": "5", "0e": "6", "0f": "7", "00": "8", "01": "9", "15": "-",
    "16": ".", "67": "_", "46": "~", "02": ":", "17": "/", "07": "?", "1b": "#",
    "63": "[", "65": "]", "78": "@", "19": "!", "1c": "$", "1e": "&", "10": "(",
    "11": ")", "12": "*", "13": "+", "14": ",", "03": ";", "05": "=", "1d": "%",
  };

  function decodeAllanimeUrl(encoded) {
    const value = encoded.startsWith("--") ? encoded.slice(2) : encoded;
    let out = "";
    for (let i = 0; i < value.length; i += 2) {
      const pair = value.substr(i, 2);
      out += HEX_MAP[pair] != null ? HEX_MAP[pair] : pair;
    }
    return out.replace(/\\u002F/g, "/").replace(/\\\|/g, "");
  }

  function parseEpisodeSourceUrls(body) {
    const enc = /"tobeparsed"\s*:\s*"([^"]+)"/.exec(body);
    if (enc) return { encrypted: enc[1] };
    try {
      const json = JSON.parse(body);
      const urls =
        json && json.data && json.data.episode && json.data.episode.sourceUrls;
      if (!Array.isArray(urls)) return null;
      return {
        plain: urls.map((j) => ({
          sourceUrl: j.sourceUrl || "",
          sourceName: j.sourceName || "",
          priority: j.priority || 0,
        })),
      };
    } catch {
      return null;
    }
  }

  async function episodeSourceUrls(showId, translationType, episodeString) {
    const candidates = [episodeString];
    if (!episodeString.includes(".")) candidates.push(episodeString + ".0");
    for (const candidate of candidates) {
      const variables = { showId, translationType, episodeString: candidate };
      // GET persisted-query first, then POST fallback.
      const extensions = JSON.stringify({
        persistedQuery: { version: 1, sha256Hash: EPISODE_GQL_HASH },
      });
      const getUrl =
        ALLANIME +
        "?variables=" + encodeURIComponent(JSON.stringify(variables)) +
        "&extensions=" + encodeURIComponent(extensions);
      let body = "";
      const getRes = await httpText(getUrl, {
        headers: { ...ALLANIME_HEADERS, Origin: "https://youtu-chan.com" },
      });
      if (getRes.body) {
        if (getRes.body.includes("NEED_CAPTCHA")) episodeNeededCaptcha = true;
        body = getRes.body;
      }
      let parsed = body ? parseEpisodeSourceUrls(body) : null;
      if (!parsed) {
        const postBody = await postJson(ALLANIME, { variables, query: EPISODE_GQL }, ALLANIME_HEADERS);
        const postStr = JSON.stringify(postBody);
        if (postStr.includes("NEED_CAPTCHA")) episodeNeededCaptcha = true;
        parsed = parseEpisodeSourceUrls(postStr);
      }
      if (!parsed) continue;
      let sources = parsed.plain;
      if (parsed.encrypted) sources = await decodeTobeparsed(parsed.encrypted);
      if (sources && sources.length) return sources;
    }
    return null;
  }

  function normalizeAllanimeUrl(v) {
    if (!v) return null;
    if (v.startsWith("//")) return "https:" + v;
    if (v.startsWith("/")) return "https://allanime.day" + v;
    if (v.startsWith("http")) return v;
    return "https://allanime.day/" + v;
  }

  function isDirectVideoUrl(v) {
    const l = (v || "").toLowerCase();
    if (l.includes("googlevideo.com")) return true;
    return /\.(mp4|webm|m4v|mov|m3u8)(\?|$)/.test(l);
  }

  function resolutionNum(v) {
    const m = /\d+/.exec((v || "") + "");
    return m ? parseInt(m[0], 10) : 0;
  }

  async function trySourceUrls(sources) {
    const decoded = sources
      .filter((s) => s.sourceUrl)
      .map((s) => {
        const path = s.sourceUrl.startsWith("--")
          ? decodeAllanimeUrl(s.sourceUrl).replace("/clock", "/clock.json")
          : s.sourceUrl;
        return { ...s, path };
      })
      .sort((a, b) => {
        const ia = PROVIDER_PRIORITY.indexOf(a.sourceName);
        const ib = PROVIDER_PRIORITY.indexOf(b.sourceName);
        return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
      });

    for (const source of decoded) {
      const fetchUrl = normalizeAllanimeUrl(source.path);
      if (!fetchUrl) continue;
      try {
        const resp = await httpText(fetchUrl, { headers: ALLMANGA_HEADERS });
        if (!resp.ok || !resp.body) continue;
        const json = JSON.parse(resp.body);
        const links = json.links;
        if (!Array.isArray(links)) continue;
        const playable = links.filter((l) => typeof l.link === "string");
        if (!playable.length) continue;
        const mp4 = playable.filter((l) => {
          const u = (l.link || "").toLowerCase();
          return !u.includes(".m3u8") && !u.includes("master.");
        });
        const chosen = (mp4.length ? mp4 : playable).sort(
          (a, b) => resolutionNum(b.resolutionStr) - resolutionNum(a.resolutionStr)
        );
        const best = chosen[0];
        if (!best || !best.link || !isDirectVideoUrl(best.link)) continue;
        return {
          url: best.link,
          resolution: best.resolutionStr || "?",
          sourceName: source.sourceName,
          referer: "https://allmanga.to",
        };
      } catch {
        continue;
      }
    }
    return null;
  }

  async function resolveAllmanga(title, episodeNumber, isMovie, translationType) {
    const dubSub = translationType === "dub" ? "dub" : "sub";
    const epStr = isMovie ? "1" : String(episodeNumber);
    const edges = await searchAllmanga(title, dubSub);
    if (!edges || !edges.length) return null;
    const anime = bestAllmangaMatch(edges, title);
    const showId = anime && anime._id;
    if (!showId) return null;
    const sourceUrls = await episodeSourceUrls(showId, dubSub, epStr);
    if (!sourceUrls || !sourceUrls.length) return null;
    return trySourceUrls(sourceUrls);
  }

  /**
   * Resolves a direct playable source for an anime episode.
   * @returns {url, referer, resolution, sourceName}
   * @throws CaptchaRequiredError when AllAnime is captcha-gated.
   */
  async function resolveSource(item, episodeNumber, opts = {}) {
    const dub = !!opts.dub;
    const translationType = dub ? "dub" : "sub";
    const isMovie = item.episodesTotal === 1 && episodeNumber === 1;
    episodeNeededCaptcha = false;

    let result = await resolveAllmanga(item.title, episodeNumber, isMovie, translationType);
    if (!result && translationType === "dub") {
      result = await resolveAllmanga(item.title, episodeNumber, isMovie, "sub");
    }
    if (result) return { ...result, provider: "AllManga" };

    if (episodeNeededCaptcha) throw new CaptchaRequiredError(CAPTCHA_URL);

    // TODO: HiAnime/Megacloud fallback (ported separately). AllAnime + captcha
    // is the primary path and covers the captcha-gated case.
    throw new Error("No playable anime source found for " + item.title + ".");
  }

  window.OmniAnime = {
    fetchAnimeCategories,
    findByTitle,
    fetchEpisodes,
    resolveSource,
    CaptchaRequiredError,
    CAPTCHA_URL,
  };
})();
