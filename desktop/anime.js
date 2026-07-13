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
// Includes a HiAnime fallback for long-running One Piece episodes when AllAnime
// has gaps in the latest range.
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

  const HIANIME_DOMAINS = [
    "https://hianime.to",
    "https://hianime.tv",
    "https://hianime.cv",
    "https://hianimes.ro",
    "https://hianime.nz",
    "https://hianime.bz",
    "https://hianime.pe",
    "https://hianime.cx",
    "https://hianime.do",
  ];
  const HIANIME_ONE_PIECE_SLUG = "one-piece-100";
  const HIANIME_ONE_PIECE_MIN_EPISODE = 1020;

  // Raised by resolveSource when AllAnime answers NEED_CAPTCHA.
  class CaptchaRequiredError extends Error {
    constructor(url) {
      super(
        "AllAnime needs a captcha solved before it will hand over sources.",
      );
      this.name = "CaptchaRequiredError";
      this.url = url;
    }
  }

  // MARK: - HTTP helpers (via main-process fetch, no CORS)

  async function httpText(
    url,
    { method = "GET", headers = {}, body = null } = {},
  ) {
    if (window.electron && window.electron.iptvFetch) {
      const res = await window.electron.iptvFetch(url, method, headers, body);
      if (!res || res.ok === false) {
        return {
          ok: false,
          status: res && res.status ? res.status : 0,
          body: "",
        };
      }
      return { ok: true, status: res.status || 200, body: res.html || "" };
    } else {
      try {
        const fetchOptions = { method, headers };
        if (body)
          fetchOptions.body =
            typeof body === "string" ? body : JSON.stringify(body);
        const response = await fetch(url, fetchOptions);
        const html = await response.text();
        return { ok: response.ok, status: response.status, body: html || "" };
      } catch (e) {
        return { ok: false, status: 0, body: "" };
      }
    }
  }

  async function postJson(url, obj, headers = {}) {
    const res = await httpText(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        ...headers,
      },
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

  function sanitizeTitle(value) {
    return (value || "")
      .replace(/[''`´]/g, "")
      .replace(/[:!.]/g, "")
      .replace(/\s+/g, " ")
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
      rating: (
        (json.averageScore != null ? json.averageScore : 0) / 10
      ).toFixed(1),
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
      {
        id: "anime_airing",
        title: "Currently Airing",
        sort: ["POPULARITY_DESC"],
        status: "RELEASING",
      },
      {
        id: "anime_this_season",
        title: `${s.label} ${s.year}`,
        sort: ["POPULARITY_DESC"],
        season: s.season,
        seasonYear: s.year,
      },
      {
        id: "anime_top_rated",
        title: "All-Time Top Rated",
        sort: ["SCORE_DESC"],
      },
      {
        id: "anime_popular",
        title: "All-Time Popular",
        sort: ["POPULARITY_DESC"],
      },
      { id: "anime_recent", title: "Recently Added", sort: ["ID_DESC"] },
      {
        id: "anime_movies",
        title: "Anime Movies",
        sort: ["SCORE_DESC"],
        format: "MOVIE",
      },
      {
        id: "anime_action",
        title: "Action",
        sort: ["POPULARITY_DESC"],
        genre: "Action",
      },
      {
        id: "anime_romance",
        title: "Romance",
        sort: ["POPULARITY_DESC"],
        genre: "Romance",
      },
      {
        id: "anime_fantasy",
        title: "Fantasy",
        sort: ["POPULARITY_DESC"],
        genre: "Fantasy",
      },
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
      return specs.map((c) => ({
        id: c.id,
        title: c.title,
        type: "anime",
        items: [],
      }));
    }
  }

  async function findByTitle(title) {
    const q = (title || "").trim();
    if (!q) return null;
    const gql = `query($search: String) { Page(page: 1, perPage: 5) { media(type: ANIME, search: $search, sort: [SEARCH_MATCH, POPULARITY_DESC], isAdult: false) { id title { romaji english native } description(asHtml: false) coverImage { extraLarge large } bannerImage genres averageScore episodes duration format seasonYear startDate { year } studios(isMain: true) { nodes { name } } } } }`;
    try {
      const body = await postJson(ANILIST, {
        query: gql,
        variables: { search: q },
      });
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
      const body = await postJson(ANILIST, {
        query: gql,
        variables: { search: title },
      });
      const eps =
        body &&
        body.data &&
        body.data.Media &&
        body.data.Media.streamingEpisodes;
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
      (e) => ((e.name || "") + "").toLowerCase().trim() === lower,
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
      search: {
        allowAdult: false,
        allowUnknown: false,
        query: (query || "").toLowerCase(),
      },
      limit: 40,
      page: 1,
      translationType,
      countryOrigin: "ALL",
    };
    const body = await postJson(
      ALLANIME,
      { variables, query: SEARCH_GQL },
      ALLANIME_HEADERS,
    );
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

  async function anilistSeasonTitle(baseTitle, seasonNumber = 1) {
    if (seasonNumber <= 1) return { title: baseTitle, romaji: null };

    const query = `
      query($search:String) {
        Media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
          title { english romaji }
          relations {
            edges {
              relationType
              node {
                type
                format
                title { english romaji }
                startDate { year }
                seasonYear
              }
            }
          }
        }
      }
    `;

    try {
      const body = await postJson(ANILIST, {
        query,
        variables: { search: baseTitle },
      });
      const media = body && body.data && body.data.Media;
      if (!media) return { title: baseTitle, romaji: null };

      const edges =
        media.relations && Array.isArray(media.relations.edges)
          ? media.relations.edges
          : [];
      const sequels = edges
        .filter((edge) => {
          const node = (edge && edge.node) || null;
          return (
            edge &&
            edge.relationType === "SEQUEL" &&
            node &&
            node.type === "ANIME" &&
            (node.format === "TV" || node.format === "TV_SHORT")
          );
        })
        .sort((a, b) => {
          const ay =
            (a && a.node && a.node.startDate && a.node.startDate.year) ||
            (a && a.node && a.node.seasonYear) ||
            9999;
          const by =
            (b && b.node && b.node.startDate && b.node.startDate.year) ||
            (b && b.node && b.node.seasonYear) ||
            9999;
          return ay - by;
        });

      const targetIndex = seasonNumber - 2;
      if (targetIndex < 0 || targetIndex >= sequels.length) {
        return { title: baseTitle, romaji: null };
      }

      const nodeTitle =
        sequels[targetIndex] &&
        sequels[targetIndex].node &&
        sequels[targetIndex].node.title
          ? sequels[targetIndex].node.title
          : null;
      return {
        title:
          (nodeTitle && (nodeTitle.english || nodeTitle.romaji)) || baseTitle,
        romaji: (nodeTitle && nodeTitle.romaji) || null,
      };
    } catch {
      return { title: baseTitle, romaji: null };
    }
  }

  const ONE_PIECE_SEASON_START_EPISODES = {
    1: 1,
    2: 62,
    3: 78,
    4: 92,
    5: 131,
    6: 144,
    7: 196,
    8: 229,
    9: 264,
    10: 326,
    11: 384,
    12: 425,
    13: 457,
    14: 491,
    15: 517,
    16: 579,
    17: 629,
    18: 747,
    19: 783,
    20: 878,
    21: 892,
    22: 1089,
  };

  function isOnePieceTitle(title) {
    const lower = (title || "").toLowerCase();
    return lower === "one piece" || lower.includes("one piece");
  }

  function hardMapOnePieceEpisode(seasonNum, episodeNum) {
    const start = ONE_PIECE_SEASON_START_EPISODES[seasonNum];
    if (!start || episodeNum <= 0) return null;
    return start + episodeNum - 1;
  }

  function normalizeEpisodeLinkage(item, seasonNumber, episodeNumber) {
    const seasonNum = Number.parseInt(seasonNumber, 10);
    const epNum = Number.parseInt(episodeNumber, 10);
    if (!Number.isFinite(seasonNum) || !Number.isFinite(epNum))
      return episodeNumber;
    if (!isOnePieceTitle(item && item.title)) return epNum;
    if (seasonNum <= 1 || epNum <= 0 || epNum >= 400) return epNum;

    const rawSeasons = Array.isArray(item && item.seasonsData)
      ? item.seasonsData
      : Array.isArray(item && item.seasons)
        ? item.seasons
        : [];

    const seasons = rawSeasons
      .map((s) => ({
        seasonNumber: Number.parseInt(
          s && (s.season_number != null ? s.season_number : s.seasonNumber),
          10,
        ),
        episodeCount: Number.parseInt(
          s && (s.episode_count != null ? s.episode_count : s.episodeCount),
          10,
        ),
      }))
      .filter(
        (s) =>
          Number.isFinite(s.seasonNumber) && Number.isFinite(s.episodeCount),
      );

    const current = seasons.find((s) => s.seasonNumber === seasonNum);
    if (!current || current.episodeCount <= 0) {
      return hardMapOnePieceEpisode(seasonNum, epNum) || epNum;
    }
    if (epNum > current.episodeCount) return epNum;

    const priorEpisodes = seasons
      .filter((s) => s.seasonNumber > 0 && s.seasonNumber < seasonNum)
      .reduce((sum, s) => sum + Math.max(0, s.episodeCount), 0);

    if (priorEpisodes > 0) return priorEpisodes + epNum;
    return hardMapOnePieceEpisode(seasonNum, epNum) || epNum;
  }

  /** Returns { count, meta } for an anime item's season. */
  async function fetchEpisodes(item, seasonNumber = 1) {
    const seasonTitle = await anilistSeasonTitle(item.title, seasonNumber);
    const searchTitle = seasonTitle.title;
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
      const cryptoKey = await crypto.subtle.importKey(
        "raw",
        key,
        { name: "AES-CTR" },
        false,
        ["decrypt"],
      );
      const plainBuf = await crypto.subtle.decrypt(
        { name: "AES-CTR", counter: iv, length: 128 },
        cryptoKey,
        ciphertext,
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
    79: "A",
    "7a": "B",
    "7b": "C",
    "7c": "D",
    "7d": "E",
    "7e": "F",
    "7f": "G",
    70: "H",
    71: "I",
    72: "J",
    73: "K",
    74: "L",
    75: "M",
    76: "N",
    77: "O",
    68: "P",
    69: "Q",
    "6a": "R",
    "6b": "S",
    "6c": "T",
    "6d": "U",
    "6e": "V",
    "6f": "W",
    60: "X",
    61: "Y",
    62: "Z",
    59: "a",
    "5a": "b",
    "5b": "c",
    "5c": "d",
    "5d": "e",
    "5e": "f",
    "5f": "g",
    50: "h",
    51: "i",
    52: "j",
    53: "k",
    54: "l",
    55: "m",
    56: "n",
    57: "o",
    48: "p",
    49: "q",
    "4a": "r",
    "4b": "s",
    "4c": "t",
    "4d": "u",
    "4e": "v",
    "4f": "w",
    40: "x",
    41: "y",
    42: "z",
    "08": "0",
    "09": "1",
    "0a": "2",
    "0b": "3",
    "0c": "4",
    "0d": "5",
    "0e": "6",
    "0f": "7",
    "00": "8",
    "01": "9",
    15: "-",
    16: ".",
    67: "_",
    46: "~",
    "02": ":",
    17: "/",
    "07": "?",
    "1b": "#",
    63: "[",
    65: "]",
    78: "@",
    19: "!",
    "1c": "$",
    "1e": "&",
    10: "(",
    11: ")",
    12: "*",
    13: "+",
    14: ",",
    "03": ";",
    "05": "=",
    "1d": "%",
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
        "?variables=" +
        encodeURIComponent(JSON.stringify(variables)) +
        "&extensions=" +
        encodeURIComponent(extensions);
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
        const postBody = await postJson(
          ALLANIME,
          { variables, query: EPISODE_GQL },
          ALLANIME_HEADERS,
        );
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
          (a, b) =>
            resolutionNum(b.resolutionStr) - resolutionNum(a.resolutionStr),
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

  async function resolveAllmanga(
    item,
    title,
    seasonNumber,
    episodeNumber,
    isMovie,
    translationType,
  ) {
    const dubSub = translationType === "dub" ? "dub" : "sub";
    const seasonTitle = isMovie
      ? { title, romaji: null }
      : await anilistSeasonTitle(title, seasonNumber);
    const linkedEpisode = isMovie
      ? 1
      : normalizeEpisodeLinkage(item || { title }, seasonNumber, episodeNumber);
    const epStr = String(linkedEpisode);

    const seen = new Set();
    const candidates = [];
    const addCandidate = (value) => {
      const v = (value || "").trim();
      if (!v || seen.has(v)) return;
      seen.add(v);
      candidates.push(v);
    };

    addCandidate(seasonTitle.title);
    addCandidate(sanitizeTitle(seasonTitle.title));
    addCandidate(seasonTitle.romaji || "");
    addCandidate(title);
    addCandidate(sanitizeTitle(title));

    let edges = null;
    let matchedTitle = seasonTitle.title;
    for (const candidate of candidates) {
      try {
        const res = await searchAllmanga(candidate, dubSub);
        if (res && res.length) {
          edges = res;
          matchedTitle = candidate;
          break;
        }
      } catch (_) {
        // Try next candidate.
      }
    }

    if (!edges || !edges.length) return null;
    const anime = bestAllmangaMatch(edges, matchedTitle);
    const showId = anime && anime._id;
    if (!showId) return null;
    const sourceUrls = await episodeSourceUrls(showId, dubSub, epStr);
    if (!sourceUrls || !sourceUrls.length) return null;
    return trySourceUrls(sourceUrls);
  }

  function parseJsonSafe(v) {
    try {
      return JSON.parse(v);
    } catch (_) {
      return null;
    }
  }

  function hianimeHeaders(base, ajax = false) {
    const headers = {
      Accept: ajax ? "application/json, text/plain, */*" : "text/html,*/*",
      Referer: `${base}/`,
      Origin: base,
    };
    if (ajax) headers["X-Requested-With"] = "XMLHttpRequest";
    return headers;
  }

  function htmlFromMaybeAjaxJson(body) {
    const parsed = parseJsonSafe(body || "");
    if (parsed && typeof parsed.html === "string") return parsed.html;
    if (parsed && parsed.data && typeof parsed.data.html === "string")
      return parsed.data.html;
    return body || "";
  }

  function stripHtml(v) {
    return String(v || "")
      .replace(/<[^>]*>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function absoluteUrl(base, value) {
    const raw = String(value || "").trim();
    if (!raw) return null;
    if (/^https?:\/\//i.test(raw)) return raw;
    if (raw.startsWith("//")) return "https:" + raw;
    try {
      return new URL(raw, base).toString();
    } catch (_) {
      return null;
    }
  }

  function extractHianimeAnimeId(watchHtml, slug) {
    const candidates = [
      /id=["']ani_detail["'][^>]*data-id=["']([^"']+)["']/i,
      /class=["'][^"']*film-detail[^"']*["'][^>]*data-id=["']([^"']+)["']/i,
      /data-id=["'](\d+)["']/i,
    ];
    for (const rx of candidates) {
      const m = rx.exec(watchHtml || "");
      if (m && m[1]) return m[1];
    }
    const tail = /-(\d+)(?:$|\?)/.exec(slug || "");
    return tail && tail[1] ? tail[1] : null;
  }

  function extractHianimeEpisodeId(listHtml, episodeNumber) {
    const ep = String(Number.parseInt(episodeNumber, 10));
    if (!ep || ep === "NaN") return null;
    const patterns = [
      new RegExp(`data-number=["']${ep}["'][^>]*data-id=["']([^"']+)["']`, "i"),
      new RegExp(`data-id=["']([^"']+)["'][^>]*data-number=["']${ep}["']`, "i"),
    ];
    for (const rx of patterns) {
      const m = rx.exec(listHtml || "");
      if (m && m[1]) return m[1];
    }
    return null;
  }

  function extractHianimeServerId(serversHtml, preferDub = false) {
    const serverRe =
      /<[^>]*data-id=["']([^"']+)["'][^>]*>([\s\S]*?)<\/[^>]+>/gi;
    const entries = [];
    let match;
    while ((match = serverRe.exec(serversHtml || ""))) {
      const id = (match[1] || "").trim();
      if (!id) continue;
      const raw = match[0] || "";
      const label = stripHtml(match[2] || "");
      const text = `${raw} ${label}`.toLowerCase();
      entries.push({ id, text });
    }

    if (!entries.length) return null;

    const preferredLane = preferDub ? "dub" : "sub";
    const score = (entry) => {
      let s = 0;
      if (entry.text.includes(preferredLane)) s += 30;
      if (!preferDub && !entry.text.includes("dub")) s += 4;
      if (
        /hd-?1|vidstream|megacloud|streamsb|streamtape|default|server\s*1/.test(
          entry.text,
        )
      ) {
        s += 20;
      }
      if (/hd-?2|server\s*2/.test(entry.text)) s += 10;
      return s;
    };

    const sorted = [...entries].sort((a, b) => score(b) - score(a));
    return sorted[0] && sorted[0].id ? sorted[0].id : entries[0].id;
  }

  function collectHttpUrls(value, out, seen = new Set()) {
    if (value == null) return;
    if (typeof value === "string") {
      const v = value.trim();
      if (/^https?:\/\//i.test(v)) out.push(v);
      return;
    }
    if (typeof value !== "object") return;
    if (seen.has(value)) return;
    seen.add(value);
    if (Array.isArray(value)) {
      for (const item of value) collectHttpUrls(item, out, seen);
      return;
    }
    for (const k of Object.keys(value)) collectHttpUrls(value[k], out, seen);
  }

  function pickHianimeDirectUrl(payload) {
    const urls = [];
    collectHttpUrls(payload, urls);
    for (const u of urls) {
      if (isDirectVideoUrl(u)) return u;
    }
    return null;
  }

  async function discoverOnePieceSlugs(base) {
    const slugs = [HIANIME_ONE_PIECE_SLUG];
    try {
      const searchUrl = `${base}/search?keyword=${encodeURIComponent("one piece")}`;
      const res = await httpText(searchUrl, { headers: hianimeHeaders(base) });
      if (!res.ok || !res.body) return slugs;
      const seen = new Set(slugs);
      const re = /href=["']\/watch\/([^"'#?\s]+)["']/gi;
      let m;
      while ((m = re.exec(res.body))) {
        const slug = (m[1] || "").trim();
        if (!slug || seen.has(slug)) continue;
        if (!slug.toLowerCase().includes("one-piece")) continue;
        if (/(movie|film|special|recap)/i.test(slug)) continue;
        seen.add(slug);
        slugs.unshift(slug);
      }
    } catch (_) {}
    return slugs;
  }

  async function resolveHianimeOnePiece(episodeNumber, dub = false) {
    const epNum = Number.parseInt(episodeNumber, 10);
    if (!Number.isFinite(epNum) || epNum <= 0) return null;

    for (const base of HIANIME_DOMAINS) {
      const slugs = await discoverOnePieceSlugs(base);
      for (const slug of slugs) {
        try {
          const watchUrl = `${base}/watch/${slug}`;
          const watchRes = await httpText(watchUrl, {
            headers: hianimeHeaders(base),
          });
          if (!watchRes.ok || !watchRes.body) continue;

          const animeId = extractHianimeAnimeId(watchRes.body, slug);
          if (!animeId) continue;

          const listUrl = `${base}/ajax/v2/episode/list/${encodeURIComponent(animeId)}`;
          const listRes = await httpText(listUrl, {
            headers: hianimeHeaders(base, true),
          });
          if (!listRes.ok || !listRes.body) continue;
          const listHtml = htmlFromMaybeAjaxJson(listRes.body);

          const episodeId = extractHianimeEpisodeId(listHtml, epNum);
          if (!episodeId) continue;

          const serversUrl = `${base}/ajax/v2/episode/servers?episodeId=${encodeURIComponent(episodeId)}`;
          const serversRes = await httpText(serversUrl, {
            headers: hianimeHeaders(base, true),
          });
          if (!serversRes.ok || !serversRes.body) continue;
          const serversHtml = htmlFromMaybeAjaxJson(serversRes.body);

          const serverId = extractHianimeServerId(serversHtml, dub);
          if (!serverId) continue;

          const sourcesUrl = `${base}/ajax/v2/episode/sources?id=${encodeURIComponent(serverId)}`;
          const sourcesRes = await httpText(sourcesUrl, {
            headers: hianimeHeaders(base, true),
          });
          if (!sourcesRes.ok || !sourcesRes.body) continue;

          const srcJson = parseJsonSafe(sourcesRes.body) || {};
          const srcData =
            srcJson.data && typeof srcJson.data === "object"
              ? srcJson.data
              : srcJson;

          const direct = pickHianimeDirectUrl(srcData);
          if (direct) {
            return {
              url: direct,
              resolution: "?",
              sourceName: "HiAnime",
              referer: `${base}/`,
              kind: "direct",
            };
          }

          const link = absoluteUrl(base, srcData.link || srcJson.link || "");
          if (link) {
            return {
              url: link,
              resolution: "Embed",
              sourceName: "HiAnime",
              referer: `${base}/`,
              kind: "embed",
            };
          }
        } catch (_) {
          // try next slug/domain
        }
      }
    }

    return null;
  }

  /**
   * Resolves a direct playable source for an anime episode.
   * @returns {url, referer, resolution, sourceName}
   * @throws CaptchaRequiredError when AllAnime is captcha-gated.
   */
  function parseJsonSafe(text) {
    try {
      return JSON.parse(text || "");
    } catch {
      return null;
    }
  }

  function stripHtml(value) {
    return (value || "")
      .replace(/<[^>]*>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function hianimeHeaders(base, ajax = false) {
    const headers = {
      Accept: ajax ? "application/json, text/plain, */*" : "text/html,*/*",
      Referer: `${base}/`,
      Origin: base,
    };
    if (ajax) headers["X-Requested-With"] = "XMLHttpRequest";
    return headers;
  }

  function absUrl(base, maybeUrl) {
    const value = (maybeUrl || "").trim();
    if (!value) return null;
    if (/^https?:\/\//i.test(value)) return value;
    if (value.startsWith("//")) return "https:" + value;
    if (value.startsWith("/")) return base + value;
    return `${base}/${value}`;
  }

  function htmlFromMaybeJsonBody(body) {
    const parsed = parseJsonSafe(body);
    if (parsed && typeof parsed.html === "string") return parsed.html;
    if (parsed && parsed.data && typeof parsed.data.html === "string") {
      return parsed.data.html;
    }
    return body || "";
  }

  function extractHianimeAnimeId(watchHtml, slug) {
    const html = watchHtml || "";
    const explicit =
      /id=["']ani_detail["'][^>]*\bdata-id=["']([^"']+)["']/i.exec(html) ||
      /id=["']watch-main["'][^>]*\bdata-id=["']([^"']+)["']/i.exec(html) ||
      /\bdata-id=["'](\d+)["']/i.exec(html);
    if (explicit && explicit[1]) return explicit[1];
    const slugMatch = /-(\d+)(?:$|\?)/.exec(slug || "");
    return slugMatch && slugMatch[1] ? slugMatch[1] : null;
  }

  function extractHianimeEpisodeId(episodeListHtml, episodeNumber) {
    const ep = Number.parseInt(episodeNumber, 10);
    if (!Number.isFinite(ep) || ep <= 0) return null;
    const html = episodeListHtml || "";
    const patternA = new RegExp(
      `data-number=["']${ep}["'][^>]*data-id=["']([^"']+)["']`,
      "i",
    );
    const patternB = new RegExp(
      `data-id=["']([^"']+)["'][^>]*data-number=["']${ep}["']`,
      "i",
    );
    const hit = patternA.exec(html) || patternB.exec(html);
    return hit && hit[1] ? hit[1] : null;
  }

  function extractHianimeServerId(serversHtml, preferDub) {
    const html = serversHtml || "";
    const matches = [];
    const re = /<[^>]*data-id=["']([^"']+)["'][^>]*>([\s\S]*?)<\/[^>]+>/gi;
    let m;
    while ((m = re.exec(html))) {
      const fullTag = m[0] || "";
      const attrs = (fullTag.split(">", 1)[0] || "").toLowerCase();
      const label = `${attrs} ${stripHtml(m[2] || "")}`.toLowerCase();
      const id = (m[1] || "").trim();
      if (!id) continue;
      matches.push({ id, label });
    }
    if (!matches.length) return null;

    const score = (entry) => {
      let s = 0;
      if (preferDub) {
        if (entry.label.includes("dub")) s += 30;
        if (entry.label.includes("sub")) s -= 8;
      } else {
        if (entry.label.includes("sub")) s += 30;
        if (entry.label.includes("dub")) s -= 8;
      }
      if (/hd\s*-?\s*1|vidstream|megacloud|streamsb/.test(entry.label)) s += 12;
      if (/hd\s*-?\s*2|default/.test(entry.label)) s += 6;
      return s;
    };

    matches.sort((a, b) => score(b) - score(a));
    return matches[0].id || null;
  }

  function collectUrlsDeep(value, out, seen) {
    if (value == null) return;
    if (typeof value === "string") {
      const v = value.trim();
      if (/^https?:\/\//i.test(v) || v.startsWith("//")) out.push(v);
      return;
    }
    if (typeof value !== "object") return;
    if (seen.has(value)) return;
    seen.add(value);

    if (Array.isArray(value)) {
      for (const entry of value) collectUrlsDeep(entry, out, seen);
      return;
    }

    for (const key of Object.keys(value)) {
      collectUrlsDeep(value[key], out, seen);
    }
  }

  function pickHianimeDirectUrl(json) {
    if (!json) return null;
    const urls = [];
    collectUrlsDeep(json.sources || null, urls, new Set());
    collectUrlsDeep(json.sourcesBackup || null, urls, new Set());
    collectUrlsDeep(json.data && json.data.sources, urls, new Set());
    collectUrlsDeep(json.data && json.data.sourcesBackup, urls, new Set());
    for (const raw of urls) {
      const url = raw.startsWith("//") ? `https:${raw}` : raw;
      if (isDirectVideoUrl(url)) return url;
    }
    return null;
  }

  async function discoverHianimeOnePieceSlugs(base) {
    const fallback = [HIANIME_ONE_PIECE_SLUG];
    try {
      const searchUrl = `${base}/search?keyword=${encodeURIComponent("one piece")}`;
      const searchRes = await httpText(searchUrl, {
        headers: hianimeHeaders(base, false),
      });
      if (!searchRes.ok || !searchRes.body) return fallback;
      const out = [];
      const seen = new Set();
      const re = /href=["']\/watch\/([^"'#?]+)[^"']*["']/gi;
      let m;
      while ((m = re.exec(searchRes.body))) {
        const slug = (m[1] || "").trim();
        if (!slug || seen.has(slug)) continue;
        const lower = slug.toLowerCase();
        if (!lower.includes("one-piece")) continue;
        if (/movie|film|special|recap/.test(lower)) continue;
        seen.add(slug);
        out.push(slug);
      }
      if (!seen.has(HIANIME_ONE_PIECE_SLUG))
        out.unshift(HIANIME_ONE_PIECE_SLUG);
      return out.length ? out : fallback;
    } catch {
      return fallback;
    }
  }

  async function resolveHianimeOnePiece(episodeNumber, dub = false) {
    const ep = Number.parseInt(episodeNumber, 10);
    if (!Number.isFinite(ep) || ep <= 0) return null;

    for (const base of HIANIME_DOMAINS) {
      let slugs = [HIANIME_ONE_PIECE_SLUG];
      try {
        slugs = await discoverHianimeOnePieceSlugs(base);
      } catch {
        slugs = [HIANIME_ONE_PIECE_SLUG];
      }

      for (const slug of slugs) {
        try {
          const watchRes = await httpText(`${base}/watch/${slug}`, {
            headers: hianimeHeaders(base, false),
          });
          if (!watchRes.ok || !watchRes.body) continue;

          const animeId = extractHianimeAnimeId(watchRes.body, slug);
          if (!animeId) continue;

          const episodeListRes = await httpText(
            `${base}/ajax/v2/episode/list/${encodeURIComponent(animeId)}`,
            { headers: hianimeHeaders(base, true) },
          );
          if (!episodeListRes.ok || !episodeListRes.body) continue;
          const episodeId = extractHianimeEpisodeId(
            htmlFromMaybeJsonBody(episodeListRes.body),
            ep,
          );
          if (!episodeId) continue;

          const serversRes = await httpText(
            `${base}/ajax/v2/episode/servers?episodeId=${encodeURIComponent(episodeId)}`,
            { headers: hianimeHeaders(base, true) },
          );
          if (!serversRes.ok || !serversRes.body) continue;
          const serverId = extractHianimeServerId(
            htmlFromMaybeJsonBody(serversRes.body),
            dub,
          );
          if (!serverId) continue;

          const srcRes = await httpText(
            `${base}/ajax/v2/episode/sources?id=${encodeURIComponent(serverId)}`,
            { headers: hianimeHeaders(base, true) },
          );
          if (!srcRes.ok || !srcRes.body) continue;

          const srcJson = parseJsonSafe(srcRes.body) || {};
          const direct = pickHianimeDirectUrl(srcJson);
          if (direct) {
            return {
              url: direct,
              resolution: "?",
              sourceName: "HiAnime",
              referer: `${base}/`,
              kind: "direct",
            };
          }

          const rawLink =
            (typeof srcJson.link === "string" && srcJson.link) ||
            (srcJson.data && typeof srcJson.data.link === "string"
              ? srcJson.data.link
              : "");
          const embedLink = absUrl(base, rawLink);
          if (embedLink) {
            return {
              url: embedLink,
              resolution: "Embed",
              sourceName: "HiAnime",
              referer: `${base}/`,
              kind: "embed",
            };
          }
        } catch {
          continue;
        }
      }
    }
    return null;
  }

  /**
   * Resolves a direct playable source for an anime episode.
   * @returns {url, referer, resolution, sourceName}
   * @throws CaptchaRequiredError when AllAnime is captcha-gated.
   */
  function parseJsonSafe(text) {
    if (!text || typeof text !== "string") return null;
    try {
      return JSON.parse(text);
    } catch {
      return null;
    }
  }

  function hianimeHeaders(baseUrl, ajax = false) {
    const headers = {
      Accept: ajax
        ? "application/json, text/plain, */*"
        : "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      Referer: `${baseUrl}/`,
      Origin: baseUrl,
    };
    if (ajax) headers["X-Requested-With"] = "XMLHttpRequest";
    return headers;
  }

  function htmlFromMaybeJsonBody(body) {
    const parsed = parseJsonSafe(body);
    if (parsed && typeof parsed.html === "string") return parsed.html;
    if (
      parsed &&
      parsed.data &&
      parsed.data.html &&
      typeof parsed.data.html === "string"
    ) {
      return parsed.data.html;
    }
    return body || "";
  }

  function absUrl(baseUrl, value) {
    if (!value || typeof value !== "string") return null;
    if (/^https?:\/\//i.test(value)) return value;
    if (value.startsWith("//")) return "https:" + value;
    if (value.startsWith("/")) return baseUrl + value;
    return `${baseUrl}/${value}`;
  }

  function extractHianimeAnimeId(watchHtml, slug) {
    const fromDataId =
      /id=["']ani_detail["'][^>]*data-id=["']([^"']+)["']/i.exec(watchHtml) ||
      /data-id=["'](\d+)["']/i.exec(watchHtml);
    if (fromDataId && fromDataId[1]) return fromDataId[1];
    const fromSlug = /-(\d+)(?:\?|$)/.exec(slug || "");
    return fromSlug ? fromSlug[1] : null;
  }

  function extractHianimeEpisodeId(listHtml, absoluteEpisode) {
    if (!listHtml) return null;
    const ep = String(absoluteEpisode).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const patterns = [
      new RegExp(`data-number=["']${ep}["'][^>]*data-id=["']([^"']+)["']`, "i"),
      new RegExp(`data-id=["']([^"']+)["'][^>]*data-number=["']${ep}["']`, "i"),
    ];
    for (const pattern of patterns) {
      const match = pattern.exec(listHtml);
      if (match && match[1]) return match[1];
    }
    return null;
  }

  function stripTags(value) {
    return (value || "")
      .replace(/<[^>]*>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function extractHianimeServerId(serversHtml, preferDub) {
    if (!serversHtml) return null;
    const candidates = [];
    const rowRegex =
      /<[^>]*data-id=["']([^"']+)["'][^>]*>([\s\S]*?)<\/[^>]+>/gi;
    let row;
    while ((row = rowRegex.exec(serversHtml))) {
      const attrs = (row[0] || "").split(">", 1)[0].toLowerCase();
      const label = `${attrs} ${stripTags(row[2] || "")}`.toLowerCase();
      const id = row[1];
      if (!id) continue;
      candidates.push({ id, label });
    }

    if (!candidates.length) {
      const fallback = /data-id=["']([^"']+)["']/i.exec(serversHtml);
      return fallback ? fallback[1] : null;
    }

    const score = (candidate) => {
      const label = candidate.label;
      let value = 0;
      if (preferDub) {
        if (label.includes("dub")) value += 20;
        if (label.includes("sub")) value -= 8;
      } else {
        if (label.includes("sub")) value += 20;
        if (label.includes("dub")) value -= 8;
      }
      if (/hd-?1|megacloud|vidstream|streamsb|streamtape/.test(label))
        value += 12;
      else if (/hd-?2|hd-?3/.test(label)) value += 6;
      return value;
    };

    candidates.sort((a, b) => score(b) - score(a));
    return candidates[0] ? candidates[0].id : null;
  }

  function collectUrlsDeep(value, out, seen = new Set()) {
    if (value == null) return;
    if (typeof value === "string") {
      const v = value.trim();
      if (/^https?:\/\//i.test(v)) out.push(v);
      return;
    }
    if (Array.isArray(value)) {
      for (const entry of value) collectUrlsDeep(entry, out, seen);
      return;
    }
    if (typeof value === "object") {
      if (seen.has(value)) return;
      seen.add(value);
      for (const key of Object.keys(value))
        collectUrlsDeep(value[key], out, seen);
    }
  }

  function pickDirectHianimeUrl(payload) {
    const urls = [];
    collectUrlsDeep(payload, urls);
    return urls.find((u) => isDirectVideoUrl(u)) || null;
  }

  async function discoverHianimeOnePieceSlugs(baseUrl) {
    const searchUrl = `${baseUrl}/search?keyword=${encodeURIComponent("one piece")}`;
    const resp = await httpText(searchUrl, {
      headers: hianimeHeaders(baseUrl),
    });
    if (!resp.ok || !resp.body) return [HIANIME_ONE_PIECE_SLUG];

    const slugs = [];
    const seen = new Set();
    const regex = /href=["']\/watch\/([^"'#?]+)["']/gi;
    let match;
    while ((match = regex.exec(resp.body))) {
      const slug = (match[1] || "").trim();
      const lower = slug.toLowerCase();
      if (!lower.includes("one-piece")) continue;
      if (
        lower.includes("movie") ||
        lower.includes("film") ||
        lower.includes("special")
      ) {
        continue;
      }
      if (!seen.has(slug)) {
        seen.add(slug);
        slugs.push(slug);
      }
    }
    if (!seen.has(HIANIME_ONE_PIECE_SLUG)) slugs.push(HIANIME_ONE_PIECE_SLUG);
    return slugs.length ? slugs : [HIANIME_ONE_PIECE_SLUG];
  }

  async function resolveHianimeOnePiece(absoluteEpisode, dub = false) {
    const episodeNum = Number.parseInt(absoluteEpisode, 10);
    if (!Number.isFinite(episodeNum) || episodeNum <= 0) return null;

    for (const baseUrl of HIANIME_DOMAINS) {
      try {
        const slugs = await discoverHianimeOnePieceSlugs(baseUrl);
        for (const slug of slugs) {
          const watchUrl = `${baseUrl}/watch/${slug}`;
          const watchResp = await httpText(watchUrl, {
            headers: hianimeHeaders(baseUrl),
          });
          if (!watchResp.ok || !watchResp.body) continue;

          const animeId = extractHianimeAnimeId(watchResp.body, slug);
          if (!animeId) continue;

          const listResp = await httpText(
            `${baseUrl}/ajax/v2/episode/list/${encodeURIComponent(animeId)}`,
            { headers: hianimeHeaders(baseUrl, true) },
          );
          if (!listResp.ok || !listResp.body) continue;
          const listHtml = htmlFromMaybeJsonBody(listResp.body);
          const episodeId = extractHianimeEpisodeId(listHtml, episodeNum);
          if (!episodeId) continue;

          const serversResp = await httpText(
            `${baseUrl}/ajax/v2/episode/servers?episodeId=${encodeURIComponent(episodeId)}`,
            { headers: hianimeHeaders(baseUrl, true) },
          );
          if (!serversResp.ok || !serversResp.body) continue;
          const serversHtml = htmlFromMaybeJsonBody(serversResp.body);
          const serverId = extractHianimeServerId(serversHtml, dub);
          if (!serverId) continue;

          const sourceResp = await httpText(
            `${baseUrl}/ajax/v2/episode/sources?id=${encodeURIComponent(serverId)}`,
            { headers: hianimeHeaders(baseUrl, true) },
          );
          if (!sourceResp.ok || !sourceResp.body) continue;

          const payload = parseJsonSafe(sourceResp.body) || {};
          const directUrl = pickDirectHianimeUrl(payload);
          if (directUrl) {
            return {
              url: directUrl,
              resolution: "?",
              sourceName: "HiAnime",
              referer: `${baseUrl}/`,
              kind: "direct",
            };
          }

          const embedCandidate =
            (typeof payload.link === "string" && payload.link) ||
            (payload.data && typeof payload.data.link === "string"
              ? payload.data.link
              : "");
          const embedUrl = absUrl(baseUrl, embedCandidate);
          if (embedUrl) {
            return {
              url: embedUrl,
              resolution: "Embed",
              sourceName: "HiAnime",
              referer: `${baseUrl}/`,
              kind: "embed",
            };
          }
        }
      } catch {
        // Try next HiAnime domain.
      }
    }

    return null;
  }

  /**
   * Resolves a direct playable source for an anime episode.
   * @returns {url, referer, resolution, sourceName}
   * @throws CaptchaRequiredError when AllAnime is captcha-gated.
   */
  function parseJsonSafe(value) {
    if (!value || typeof value !== "string") return null;
    try {
      return JSON.parse(value);
    } catch (_) {
      return null;
    }
  }

  function stripHtml(value) {
    return String(value || "")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function absUrl(base, value) {
    const v = (value || "").trim();
    if (!v) return null;
    try {
      return new URL(v, base).toString();
    } catch (_) {
      return null;
    }
  }

  function hianimeHeaders(base, ajax = false) {
    const headers = {
      Accept: ajax
        ? "application/json, text/plain, */*"
        : "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      Referer: `${base}/`,
      Origin: base,
    };
    if (ajax) headers["X-Requested-With"] = "XMLHttpRequest";
    return headers;
  }

  function htmlFromMaybeJsonBody(raw) {
    const parsed = parseJsonSafe(raw);
    if (parsed && typeof parsed.html === "string") return parsed.html;
    if (parsed && parsed.data && typeof parsed.data.html === "string") {
      return parsed.data.html;
    }
    return raw || "";
  }

  function extractHianimeAnimeId(watchHtml, slug) {
    const patterns = [
      /id=["']ani_detail["'][^>]*data-id=["']([^"']+)["']/i,
      /class=["'][^"']*film-stats[^"']*["'][^>]*data-id=["']([^"']+)["']/i,
      /data-id=["']([0-9]{2,})["']/i,
    ];
    for (const pattern of patterns) {
      const m = pattern.exec(watchHtml || "");
      if (m && m[1]) return m[1];
    }
    const slugMatch = /-([0-9]{2,})$/.exec((slug || "").trim());
    return slugMatch && slugMatch[1] ? slugMatch[1] : null;
  }

  function extractHianimeEpisodeId(episodeListHtml, episodeNumber) {
    const ep = String(episodeNumber).trim();
    if (!ep) return null;
    const patterns = [
      new RegExp(`data-number=["']${ep}["'][^>]*data-id=["']([^"']+)["']`, "i"),
      new RegExp(`data-id=["']([^"']+)["'][^>]*data-number=["']${ep}["']`, "i"),
      new RegExp(`data-num=["']${ep}["'][^>]*data-id=["']([^"']+)["']`, "i"),
      new RegExp(`data-id=["']([^"']+)["'][^>]*data-num=["']${ep}["']`, "i"),
    ];
    for (const pattern of patterns) {
      const m = pattern.exec(episodeListHtml || "");
      if (m && m[1]) return m[1];
    }
    return null;
  }

  function extractHianimeServerId(serversHtml, preferDub) {
    const html = serversHtml || "";
    const entries = [];
    const re = /<[^>]*data-id=["']([^"']+)["'][^>]*>([\s\S]*?)<\/[^>]+>/gi;
    let m;
    while ((m = re.exec(html))) {
      const attrs = m[0].split(">", 1)[0].toLowerCase();
      const text = stripHtml(m[2]).toLowerCase();
      const joined = `${attrs} ${text}`;
      if (!joined.includes("server") && !/hd|stream|cloud|vid/.test(joined)) {
        continue;
      }
      entries.push({ id: m[1], label: joined });
    }

    const fallbackIds = [...html.matchAll(/data-id=["']([^"']+)["']/gi)].map(
      (v) => v[1],
    );
    if (!entries.length) return fallbackIds[0] || null;

    const score = (entry) => {
      let s = 0;
      if (preferDub) {
        if (entry.label.includes("dub")) s += 25;
        if (entry.label.includes("sub")) s -= 8;
      } else {
        if (entry.label.includes("sub")) s += 25;
        if (entry.label.includes("dub")) s -= 8;
      }
      if (/hd-?1|megacloud|vidstream|streamsb|server-?1/.test(entry.label))
        s += 14;
      if (/hd-?2|server-?2/.test(entry.label)) s += 8;
      return s;
    };

    entries.sort((a, b) => score(b) - score(a));
    return entries[0] ? entries[0].id : fallbackIds[0] || null;
  }

  function collectStringUrls(value, out, seen = new Set()) {
    if (value == null) return;
    if (typeof value === "string") {
      if (/^https?:\/\//i.test(value) && !seen.has(value)) {
        seen.add(value);
        out.push(value);
      }
      return;
    }
    if (Array.isArray(value)) {
      for (const v of value) collectStringUrls(v, out, seen);
      return;
    }
    if (typeof value === "object") {
      for (const v of Object.values(value)) collectStringUrls(v, out, seen);
    }
  }

  function pickHianimeDirectUrl(sourceJson) {
    const candidates = [];
    collectStringUrls(sourceJson, candidates);
    return candidates.find((u) => isDirectVideoUrl(u)) || null;
  }

  async function discoverOnePieceSlugs(base) {
    const out = [HIANIME_ONE_PIECE_SLUG];
    try {
      const searchUrl = `${base}/search?keyword=${encodeURIComponent("one piece")}`;
      const res = await httpText(searchUrl, { headers: hianimeHeaders(base) });
      if (!res.ok || !res.body) return out;
      const matches = [
        ...res.body.matchAll(/href=["']\/watch\/([^"'#?]+)(?:\?[^"']*)?["']/gi),
      ];
      for (const hit of matches) {
        const slug = (hit && hit[1] ? hit[1] : "").trim();
        if (!slug) continue;
        const lower = slug.toLowerCase();
        if (!lower.includes("one-piece")) continue;
        if (/movie|film|special|ova/.test(lower)) continue;
        if (!out.includes(slug)) out.unshift(slug);
      }
    } catch (_) {}
    return out;
  }

  async function resolveHianimeOnePiece(episodeNumber, dub = false) {
    const epNum = Number.parseInt(episodeNumber, 10);
    if (!Number.isFinite(epNum) || epNum <= 0) return null;

    for (const base of HIANIME_DOMAINS) {
      try {
        const slugs = await discoverOnePieceSlugs(base);
        for (const slug of slugs) {
          const watchRes = await httpText(`${base}/watch/${slug}`, {
            headers: hianimeHeaders(base),
          });
          if (!watchRes.ok || !watchRes.body) continue;

          const animeId = extractHianimeAnimeId(watchRes.body, slug);
          if (!animeId) continue;

          const listRes = await httpText(
            `${base}/ajax/v2/episode/list/${encodeURIComponent(animeId)}`,
            { headers: hianimeHeaders(base, true) },
          );
          if (!listRes.ok || !listRes.body) continue;

          const listHtml = htmlFromMaybeJsonBody(listRes.body);
          const episodeId = extractHianimeEpisodeId(listHtml, epNum);
          if (!episodeId) continue;

          const serversRes = await httpText(
            `${base}/ajax/v2/episode/servers?episodeId=${encodeURIComponent(episodeId)}`,
            { headers: hianimeHeaders(base, true) },
          );
          if (!serversRes.ok || !serversRes.body) continue;

          const serversHtml = htmlFromMaybeJsonBody(serversRes.body);
          const serverId = extractHianimeServerId(serversHtml, dub);
          if (!serverId) continue;

          const srcRes = await httpText(
            `${base}/ajax/v2/episode/sources?id=${encodeURIComponent(serverId)}`,
            { headers: hianimeHeaders(base, true) },
          );
          if (!srcRes.ok || !srcRes.body) continue;

          const srcJson = parseJsonSafe(srcRes.body) || {};
          const direct = pickHianimeDirectUrl(srcJson);
          if (direct) {
            return {
              url: direct,
              resolution: "?",
              sourceName: "HiAnime",
              referer: `${base}/`,
              kind: "direct",
            };
          }

          const linkRaw =
            (typeof srcJson.link === "string" && srcJson.link) ||
            (srcJson.data && typeof srcJson.data.link === "string"
              ? srcJson.data.link
              : null);
          const link = absUrl(base, linkRaw);
          if (link) {
            return {
              url: link,
              resolution: "Embed",
              sourceName: "HiAnime",
              referer: `${base}/`,
              kind: "embed",
            };
          }
        }
      } catch (_) {
        // Try next domain.
      }
    }

    return null;
  }

  /**
   * Resolves a direct playable source for an anime episode.
   * @returns {url, referer, resolution, sourceName}
   * @throws CaptchaRequiredError when AllAnime is captcha-gated.
   */
  function parseJsonSafe(value) {
    try {
      return JSON.parse(value);
    } catch {
      return null;
    }
  }

  function hianimeHeaders(base, ajax = false) {
    const headers = {
      Accept: ajax ? "application/json, text/plain, */*" : "text/html,*/*",
      Referer: `${base}/`,
      Origin: base,
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    };
    if (ajax) headers["X-Requested-With"] = "XMLHttpRequest";
    return headers;
  }

  function htmlFromMaybeJsonBody(body) {
    const parsed = parseJsonSafe(body || "");
    if (parsed && typeof parsed.html === "string") return parsed.html;
    return body || "";
  }

  function firstCapture(text, regex) {
    const m = regex.exec(text || "");
    return m && m[1] ? m[1] : null;
  }

  function stripTags(value) {
    return (value || "")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function absoluteUrl(base, value) {
    const v = (value || "").trim();
    if (!v) return null;
    if (v.startsWith("http://") || v.startsWith("https://")) return v;
    if (v.startsWith("//")) return `https:${v}`;
    if (v.startsWith("/")) return `${base}${v}`;
    return `${base}/${v}`;
  }

  function extractHianimeAnimeId(watchHtml, slug) {
    const fromDataId =
      firstCapture(
        watchHtml,
        /id=["']anime-info["'][^>]*data-id=["']([^"']+)["']/i,
      ) || firstCapture(watchHtml, /data-id=["'](\d+)["']/i);
    if (fromDataId) return fromDataId;
    const fromSlug = firstCapture(slug || "", /-(\d+)(?:$|\?)/);
    return fromSlug;
  }

  function extractHianimeEpisodeId(episodeListHtml, episodeNumber) {
    const ep = String(episodeNumber);
    const patterns = [
      new RegExp(`data-number=["']${ep}["'][^>]*data-id=["']([^"']+)["']`, "i"),
      new RegExp(`data-id=["']([^"']+)["'][^>]*data-number=["']${ep}["']`, "i"),
    ];
    for (const regex of patterns) {
      const id = firstCapture(episodeListHtml, regex);
      if (id) return id;
    }
    return null;
  }

  function extractHianimeServerId(serversHtml, preferDub) {
    const candidates = [];
    const re = /<[^>]*data-id=["']([^"']+)["'][^>]*>([\s\S]*?)<\/[^>]+>/gi;
    let m;
    while ((m = re.exec(serversHtml || ""))) {
      const id = (m[1] || "").trim();
      if (!id) continue;
      const rawTag = (m[0] || "").split(">", 1)[0].toLowerCase();
      const text = stripTags(m[2] || "").toLowerCase();
      const label = `${rawTag} ${text}`;
      candidates.push({ id, label });
    }
    if (!candidates.length) {
      return firstCapture(serversHtml || "", /data-id=["']([^"']+)["']/i);
    }

    const weighted = candidates.map((c) => {
      let score = 0;
      if (preferDub) {
        if (c.label.includes("dub")) score += 30;
        if (c.label.includes("sub")) score -= 6;
      } else {
        if (c.label.includes("sub")) score += 30;
        if (c.label.includes("dub")) score -= 6;
      }
      if (/hd-?1|vidstream|megacloud|streamsb/.test(c.label)) score += 20;
      if (/hd-?2|default|server-?1/.test(c.label)) score += 12;
      return { ...c, score };
    });

    weighted.sort((a, b) => b.score - a.score);
    return weighted[0] && weighted[0].id ? weighted[0].id : null;
  }

  function collectHttpUrlsDeep(value, out, seen = new Set()) {
    if (value == null) return;
    if (typeof value === "string") {
      if (/^https?:\/\//i.test(value)) out.push(value);
      return;
    }
    if (typeof value !== "object") return;
    if (seen.has(value)) return;
    seen.add(value);
    if (Array.isArray(value)) {
      for (const v of value) collectHttpUrlsDeep(v, out, seen);
      return;
    }
    for (const key of Object.keys(value)) {
      collectHttpUrlsDeep(value[key], out, seen);
    }
  }

  function pickHianimeDirectUrl(sourceJson) {
    const urls = [];
    collectHttpUrlsDeep(sourceJson, urls);
    return urls.find((u) => isDirectVideoUrl(u)) || null;
  }

  async function discoverHianimeOnePieceSlugs(base) {
    const slugs = [];
    slugs.push(HIANIME_ONE_PIECE_SLUG);
    try {
      const searchUrl = `${base}/search?keyword=${encodeURIComponent("one piece")}`;
      const res = await httpText(searchUrl, { headers: hianimeHeaders(base) });
      if (!res.ok || !res.body) return slugs;
      const re = /href=["']\/watch\/([^"'?#\s]+)["']/gi;
      let m;
      while ((m = re.exec(res.body))) {
        const slug = (m[1] || "").trim();
        if (!slug) continue;
        const lower = slug.toLowerCase();
        if (!lower.includes("one-piece")) continue;
        if (/(movie|film|special|ova)/.test(lower)) continue;
        if (!slugs.includes(slug)) slugs.unshift(slug);
      }
    } catch (_) {}
    return slugs;
  }

  async function resolveHianimeOnePiece(episodeNumber, dub = false) {
    const episodeNum = Number.parseInt(episodeNumber, 10);
    if (!Number.isFinite(episodeNum) || episodeNum <= 0) return null;

    for (const base of HIANIME_DOMAINS) {
      const slugs = await discoverHianimeOnePieceSlugs(base);
      for (const slug of slugs) {
        try {
          const watchUrl = `${base}/watch/${slug}`;
          const watchRes = await httpText(watchUrl, {
            headers: hianimeHeaders(base),
          });
          if (!watchRes.ok || !watchRes.body) continue;

          const animeId = extractHianimeAnimeId(watchRes.body, slug);
          if (!animeId) continue;

          const listUrl = `${base}/ajax/v2/episode/list/${encodeURIComponent(animeId)}`;
          const listRes = await httpText(listUrl, {
            headers: hianimeHeaders(base, true),
          });
          if (!listRes.ok || !listRes.body) continue;

          const listHtml = htmlFromMaybeJsonBody(listRes.body);
          const episodeId = extractHianimeEpisodeId(listHtml, episodeNum);
          if (!episodeId) continue;

          const serversUrl = `${base}/ajax/v2/episode/servers?episodeId=${encodeURIComponent(episodeId)}`;
          const serversRes = await httpText(serversUrl, {
            headers: hianimeHeaders(base, true),
          });
          if (!serversRes.ok || !serversRes.body) continue;

          const serversHtml = htmlFromMaybeJsonBody(serversRes.body);
          const serverId = extractHianimeServerId(serversHtml, dub);
          if (!serverId) continue;

          const sourceUrl = `${base}/ajax/v2/episode/sources?id=${encodeURIComponent(serverId)}`;
          const sourceRes = await httpText(sourceUrl, {
            headers: hianimeHeaders(base, true),
          });
          if (!sourceRes.ok || !sourceRes.body) continue;

          const sourceJson = parseJsonSafe(sourceRes.body) || {};
          const directUrl = pickHianimeDirectUrl(sourceJson);
          if (directUrl) {
            return {
              url: directUrl,
              resolution: "?",
              sourceName: "HiAnime",
              referer: `${base}/`,
              kind: "direct",
            };
          }

          const link =
            (typeof sourceJson.link === "string" && sourceJson.link) ||
            (sourceJson.data && typeof sourceJson.data.link === "string"
              ? sourceJson.data.link
              : "");
          const embedUrl = absoluteUrl(base, link);
          if (embedUrl) {
            return {
              url: embedUrl,
              resolution: "Embed",
              sourceName: "HiAnime",
              referer: `${base}/`,
              kind: "embed",
            };
          }
        } catch (_) {
          continue;
        }
      }
    }

    return null;
  }

  /**
   * Resolves a direct playable source for an anime episode.
   * @returns {url, referer, resolution, sourceName}
   * @throws CaptchaRequiredError when AllAnime is captcha-gated.
   */
  function parseJsonSafe(text) {
    try {
      return JSON.parse(text || "");
    } catch {
      return null;
    }
  }

  function htmlFromAjaxPayload(text) {
    const parsed = parseJsonSafe(text);
    if (parsed && typeof parsed.html === "string") return parsed.html;
    return text || "";
  }

  function hianimeHeaders(base, ajax = false) {
    const headers = {
      Accept: ajax ? "application/json, text/plain, */*" : "text/html,*/*",
      Referer: base + "/",
      Origin: base,
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    };
    if (ajax) headers["X-Requested-With"] = "XMLHttpRequest";
    return headers;
  }

  function extractHianimeAnimeId(watchHtml, slug) {
    if (!watchHtml) return null;
    const patterns = [
      /class=["'][^"']*film-stats[^"']*["'][^>]*data-id=["']([^"']+)["']/i,
      /id=["']ani_detail["'][^>]*data-id=["']([^"']+)["']/i,
      /data-id=["'](\d+)["']/i,
    ];
    for (const re of patterns) {
      const match = re.exec(watchHtml);
      if (match && match[1]) return match[1];
    }
    const slugMatch = /-(\d+)(?:\?|$)/.exec(slug || "");
    return slugMatch && slugMatch[1] ? slugMatch[1] : null;
  }

  function extractHianimeEpisodeId(episodeListHtml, episodeNumber) {
    const ep = String(episodeNumber);
    const patterns = [
      new RegExp(`data-number=["']${ep}["'][^>]*data-id=["']([^"']+)["']`, "i"),
      new RegExp(`data-id=["']([^"']+)["'][^>]*data-number=["']${ep}["']`, "i"),
      new RegExp(`\\bep\\s*${ep}\\b[^>]*data-id=["']([^"']+)["']`, "i"),
    ];
    for (const re of patterns) {
      const match = re.exec(episodeListHtml || "");
      if (match && match[1]) return match[1];
    }
    return null;
  }

  function extractHianimeServerCandidates(serversHtml) {
    const out = [];
    const re = /<[^>]*data-id=["']([^"']+)["'][^>]*>([\s\S]*?)<\/[^>]+>/gi;
    let match;
    while ((match = re.exec(serversHtml || "")) !== null) {
      const id = (match[1] || "").trim();
      if (!id) continue;
      const fullTag = (match[0] || "").toLowerCase();
      const text = (match[2] || "")
        .replace(/<[^>]*>/g, " ")
        .trim()
        .toLowerCase();
      const lane =
        fullTag.includes("dub") || text.includes("dub")
          ? "dub"
          : fullTag.includes("sub") || text.includes("sub")
            ? "sub"
            : "";
      out.push({ id, text, fullTag, lane });
    }
    const dedup = [];
    const seen = new Set();
    for (const c of out) {
      if (seen.has(c.id)) continue;
      seen.add(c.id);
      dedup.push(c);
    }
    return dedup;
  }

  function pickHianimeServerId(serversHtml, preferDub) {
    const candidates = extractHianimeServerCandidates(serversHtml);
    if (!candidates.length) return null;
    const lane = preferDub ? "dub" : "sub";
    const laneCandidates = candidates.filter((c) => c.lane === lane);
    const preferredPool = laneCandidates.length ? laneCandidates : candidates;
    const score = (c) => {
      const hay = `${c.text} ${c.fullTag}`;
      if (hay.includes("hd-1") || hay.includes("hd 1")) return 0;
      if (hay.includes("vidstream") || hay.includes("megacloud")) return 1;
      if (hay.includes("hd-2") || hay.includes("hd 2")) return 2;
      return 9;
    };
    preferredPool.sort((a, b) => score(a) - score(b));
    return preferredPool[0] && preferredPool[0].id ? preferredPool[0].id : null;
  }

  function collectHttpUrls(value, out) {
    if (value == null) return;
    if (typeof value === "string") {
      if (/^https?:\/\//i.test(value)) out.push(value);
      return;
    }
    if (Array.isArray(value)) {
      for (const entry of value) collectHttpUrls(entry, out);
      return;
    }
    if (typeof value === "object") {
      for (const key of Object.keys(value)) collectHttpUrls(value[key], out);
    }
  }

  function pickHianimeDirectUrl(payload) {
    const urls = [];
    if (payload && typeof payload === "object") {
      collectHttpUrls(payload.sources || null, urls);
      collectHttpUrls(payload.sourcesBackup || null, urls);
      // Fallback in case the API shape changes.
      collectHttpUrls(payload, urls);
    }
    return urls.find((u) => isDirectVideoUrl(u)) || null;
  }

  async function discoverAnimeSlug(base, title) {
    try {
      const searchUrl = `${base}/search?keyword=${encodeURIComponent(title)}`;
      const res = await httpText(searchUrl, { headers: hianimeHeaders(base) });
      if (!res.ok || !res.body) return null;
      const matches = [];
      const re = /href=["']\/watch\/([^"'#?\s]+)["']/gi;
      let m;
      while ((m = re.exec(res.body)) !== null) {
        const slug = decodeURIComponent((m[1] || "").trim());
        if (!slug) continue;
        const lower = slug.toLowerCase();
        if (
          lower.includes("movie") ||
          lower.includes("film") ||
          lower.includes("special")
        ) {
          continue;
        }
        if (!matches.includes(slug)) matches.push(slug);
      }
      return matches[0] || null;
    } catch (_) {
      return null;
    }
  }

  async function resolveAnimeFromHianime(
    title,
    episodeNumber,
    preferDub = false,
  ) {
    const epNum = Number.parseInt(episodeNumber, 10);
    if (!Number.isFinite(epNum) || epNum <= 0) return null;

    for (const base of HIANIME_DOMAINS) {
      try {
        const slug = await discoverAnimeSlug(base, title);
        if (!slug) continue;

        const watchUrl = `${base}/watch/${slug}`;
        const watchRes = await httpText(watchUrl, {
          headers: hianimeHeaders(base),
        });
        if (!watchRes.ok || !watchRes.body) continue;

        const animeId = extractHianimeAnimeId(watchRes.body, slug);
        if (!animeId) continue;

        const listRes = await httpText(
          `${base}/ajax/v2/episode/list/${encodeURIComponent(animeId)}`,
          { headers: hianimeHeaders(base, true) },
        );
        if (!listRes.ok || !listRes.body) continue;
        const listHtml = htmlFromAjaxPayload(listRes.body);
        const episodeId = extractHianimeEpisodeId(listHtml, epNum);
        if (!episodeId) continue;

        const serversRes = await httpText(
          `${base}/ajax/v2/episode/servers?episodeId=${encodeURIComponent(episodeId)}`,
          { headers: hianimeHeaders(base, true) },
        );
        if (!serversRes.ok || !serversRes.body) continue;
        const serversHtml = htmlFromAjaxPayload(serversRes.body);
        const serverId = pickHianimeServerId(serversHtml, preferDub);
        if (!serverId) continue;

        const sourcesRes = await httpText(
          `${base}/ajax/v2/episode/sources?id=${encodeURIComponent(serverId)}`,
          { headers: hianimeHeaders(base, true) },
        );
        if (!sourcesRes.ok || !sourcesRes.body) continue;

        const sourcesJson = parseJsonSafe(sourcesRes.body) || {};
        const direct = pickHianimeDirectUrl(sourcesJson);
        if (direct) {
          return {
            url: direct,
            resolution: "?",
            sourceName: "HiAnime",
            referer: `${base}/`,
            kind: "direct",
          };
        }

        const link =
          typeof sourcesJson.link === "string" ? sourcesJson.link.trim() : "";
        if (link.startsWith("http")) {
          return {
            url: link,
            resolution: "Embed",
            sourceName: "HiAnime",
            referer: `${base}/`,
            kind: "embed",
          };
        }
      } catch (_) {
        // try next domain
      }
    }
    return null;
  }

  /**
   * Resolves a direct playable source for an anime episode.
   * @returns {url, referer, resolution, sourceName, kind?}
   * @throws CaptchaRequiredError when AllAnime is captcha-gated.
   */
  async function resolveSource(item, episodeNumber, opts = {}) {
    const dub = !!opts.dub;
    const translationType = dub ? "dub" : "sub";
    const seasonNumber = Number.parseInt(opts.seasonNumber || "1", 10) || 1;
    const isMovie = item.episodesTotal === 1 && episodeNumber === 1;
    episodeNeededCaptcha = false;

    // Try HiAnime first for all anime (First preference)
    try {
      const hianimeResult = await resolveAnimeFromHianime(
        item.title,
        episodeNumber,
        dub,
      );
      if (hianimeResult) return hianimeResult;
    } catch (_) {}

    // Try AllAnime (AllManga) as fallback
    let result = await resolveAllmanga(
      item,
      item.title,
      seasonNumber,
      episodeNumber,
      isMovie,
      translationType,
    );
    if (!result && translationType === "dub") {
      result = await resolveAllmanga(
        item,
        item.title,
        seasonNumber,
        episodeNumber,
        isMovie,
        "sub",
      );
    }
    if (result) return { ...result, provider: "AllManga", kind: "direct" };

    if (episodeNeededCaptcha) throw new CaptchaRequiredError(CAPTCHA_URL);

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
