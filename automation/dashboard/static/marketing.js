(() => {
  const HASH_KEY = "wf_dash_marketing_hashtags";
  const SNIPPET_KEY = "wf_dash_marketing_snippets";
  const DEFAULT_SNIPPETS = ["URL", "CTA", "https://"];

  const form = document.getElementById("mkt-form");
  const landing = document.getElementById("mkt-landing");
  const compose = document.getElementById("mkt-compose");
  const detail = document.getElementById("mkt-detail");
  const platformPane = document.getElementById("mkt-platform");
  const platformDetail = document.getElementById("mkt-platform-detail");
  if (!form || !landing || !compose || !detail || !platformPane || !platformDetail) {
    return;
  }

  const els = {
    subtabs: document.getElementById("mkt-subtabs"),
    createNew: document.getElementById("mkt-create-new"),
    composeBack: document.getElementById("mkt-compose-back"),
    detailBack: document.getElementById("mkt-detail-back"),
    postList: document.getElementById("mkt-post-list"),
    listEmpty: document.getElementById("mkt-list-empty"),
    listStatus: document.getElementById("mkt-list-status"),
    detailTitle: document.getElementById("mkt-detail-title"),
    detailMeta: document.getElementById("mkt-detail-meta"),
    detailJson: document.getElementById("mkt-detail-json"),
    metrics: document.getElementById("mkt-metrics"),
    metricsRefresh: document.getElementById("mkt-metrics-refresh"),
    metricsStatus: document.getElementById("mkt-metrics-status"),
    metricsFacebook: document.getElementById("mkt-metrics-facebook"),
    metricsFacebookDl: document.getElementById("mkt-metrics-facebook-dl"),
    metricsFacebookWarn: document.getElementById("mkt-metrics-facebook-warn"),
    metricsYoutube: document.getElementById("mkt-metrics-youtube"),
    metricsYoutubeDl: document.getElementById("mkt-metrics-youtube-dl"),
    metricsYoutubeWarn: document.getElementById("mkt-metrics-youtube-warn"),
    platformFilter: document.getElementById("mkt-platform-filter"),
    platformRefresh: document.getElementById("mkt-platform-refresh"),
    platformStatus: document.getElementById("mkt-platform-status"),
    platformList: document.getElementById("mkt-platform-list"),
    platformEmpty: document.getElementById("mkt-platform-empty"),
    platformMoreWrap: document.getElementById("mkt-platform-more-wrap"),
    platformMore: document.getElementById("mkt-platform-more"),
    platformDetailBack: document.getElementById("mkt-platform-detail-back"),
    platformDetailTitle: document.getElementById("mkt-platform-detail-title"),
    platformDetailMeta: document.getElementById("mkt-platform-detail-meta"),
    platformDetailJson: document.getElementById("mkt-platform-detail-json"),
    platformMetricsRefresh: document.getElementById("mkt-platform-metrics-refresh"),
    platformMetricsStatus: document.getElementById("mkt-platform-metrics-status"),
    platformMetricsFacebook: document.getElementById("mkt-platform-metrics-facebook"),
    platformMetricsFacebookDl: document.getElementById(
      "mkt-platform-metrics-facebook-dl"
    ),
    platformMetricsFacebookWarn: document.getElementById(
      "mkt-platform-metrics-facebook-warn"
    ),
    platformMetricsYoutube: document.getElementById("mkt-platform-metrics-youtube"),
    platformMetricsYoutubeDl: document.getElementById(
      "mkt-platform-metrics-youtube-dl"
    ),
    platformMetricsYoutubeWarn: document.getElementById(
      "mkt-platform-metrics-youtube-warn"
    ),
    title: document.getElementById("mkt-title"),
    description: document.getElementById("mkt-description"),
    media: document.getElementById("mkt-media"),
    mediaHint: document.getElementById("mkt-media-hint"),
    hashtagInput: document.getElementById("mkt-hashtag-input"),
    hashtagAdd: document.getElementById("mkt-hashtag-add"),
    hashtagSelected: document.getElementById("mkt-hashtag-selected"),
    hashtagLibrary: document.getElementById("mkt-hashtag-library"),
    snippetList: document.getElementById("mkt-snippet-list"),
    snippetInput: document.getElementById("mkt-snippet-input"),
    snippetAdd: document.getElementById("mkt-snippet-add"),
    error: document.getElementById("mkt-error"),
    warn: document.getElementById("mkt-warn"),
    preview: document.getElementById("mkt-preview"),
    previewJson: document.getElementById("mkt-preview-json"),
    fbType: document.getElementById("mkt-fb-type"),
    fbLinkWrap: document.getElementById("mkt-fb-link-wrap"),
    fbScheduleLater: document.getElementById("mkt-fb-schedule-later"),
    fbScheduleWrap: document.getElementById("mkt-fb-schedule-wrap"),
    ytScheduleLater: document.getElementById("mkt-yt-schedule-later"),
    ytScheduleWrap: document.getElementById("mkt-yt-schedule-wrap"),
    ttScheduleLater: document.getElementById("mkt-tt-schedule-later"),
    ttScheduleWrap: document.getElementById("mkt-tt-schedule-wrap"),
    ytPlaylist: document.getElementById("mkt-yt-playlist"),
    ytPlaylistStatus: document.getElementById("mkt-yt-playlist-status"),
    ytPlaylistRefresh: document.getElementById("mkt-yt-playlist-refresh"),
  };

  /** @type {string[]} */
  let selectedHashtags = [];
  /** @type {string[]} */
  let hashtagLibrary = loadLocalJson(HASH_KEY, []);
  /** @type {string[]} */
  let snippets = loadLocalJson(SNIPPET_KEY, DEFAULT_SNIPPETS.slice());
  /** @type {Array<{id:string,title:string,platforms?:string[],created_at?:string}>} */
  let postSummaries = [];
  /** @type {string|null} */
  let activeDetailPostId = null;
  /** @type {boolean} */
  let activeDetailHasFb = false;
  /** @type {boolean} */
  let activeDetailHasYt = false;
  /** @type {"saved"|"platform"} */
  let activeMktTab = "saved";
  /** @type {Array<object>} */
  let platformPosts = [];
  /** @type {string|null} */
  let platformCursor = null;
  /** @type {string|null} */
  let activePlatformObjectId = null;
  /** @type {string} */
  let activePlatformName = "facebook";
  /** @type {Array<{id:string,title:string}>} */
  let youtubePlaylists = [];
  let youtubePlaylistsLoaded = false;
  let youtubePlaylistsLoading = false;

  function loadLocalJson(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      if (!raw) {
        return fallback;
      }
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : fallback;
    } catch (_err) {
      return fallback;
    }
  }

  function saveLocalJson(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch (_err) {
      /* ignore */
    }
  }

  function showScreen(name) {
    landing.hidden = name !== "landing";
    compose.hidden = name !== "compose";
    detail.hidden = name !== "detail";
    platformPane.hidden = name !== "platform";
    platformDetail.hidden = name !== "platform-detail";
    if (els.subtabs) {
      const hideSubs = name === "compose";
      els.subtabs.hidden = hideSubs;
    }
  }

  function setMarketingTab(tab) {
    activeMktTab = tab === "platform" ? "platform" : "saved";
    if (els.subtabs) {
      els.subtabs.querySelectorAll(".marketing-subtab").forEach((btn) => {
        const on = btn.dataset.mktTab === activeMktTab;
        btn.classList.toggle("active", on);
      });
    }
    if (activeMktTab === "platform") {
      showScreen("platform");
      // Only fetch when the list is empty (first open / after filter reset).
      if (!platformPosts.length) {
        loadPlatformPosts({ reset: true });
      }
    } else {
      showScreen("landing");
      loadPosts();
    }
  }

  function normalizeHashtag(raw) {
    let tag = String(raw || "").trim();
    if (!tag) {
      return "";
    }
    if (!tag.startsWith("#")) {
      tag = `#${tag}`;
    }
    tag = tag.replace(/\s+/g, "");
    return tag.length > 1 ? tag : "";
  }

  function selectedPlatforms() {
    return [...form.querySelectorAll('input[name="platform"]:checked')].map(
      (el) => el.value
    );
  }

  function syncPlatformPanels() {
    const selected = new Set(selectedPlatforms());
    form.querySelectorAll("[data-platform-opts]").forEach((panel) => {
      const key = panel.getAttribute("data-platform-opts");
      panel.hidden = !selected.has(key);
    });
    if (selected.has("youtube")) {
      ensureYoutubePlaylists();
    }
  }

  function setYtPlaylistStatus(text, isError) {
    if (!els.ytPlaylistStatus) {
      return;
    }
    if (!text) {
      els.ytPlaylistStatus.hidden = true;
      els.ytPlaylistStatus.textContent = "";
      return;
    }
    els.ytPlaylistStatus.hidden = false;
    els.ytPlaylistStatus.textContent = text;
    els.ytPlaylistStatus.classList.toggle("marketing-hint-error", Boolean(isError));
  }

  function fillYoutubePlaylistSelect(keepId) {
    if (!els.ytPlaylist) {
      return;
    }
    const previous = keepId || els.ytPlaylist.value || "";
    els.ytPlaylist.replaceChildren();
    const none = document.createElement("option");
    none.value = "";
    none.textContent = "— none —";
    els.ytPlaylist.appendChild(none);
    for (const pl of youtubePlaylists) {
      const opt = document.createElement("option");
      opt.value = pl.id;
      opt.textContent = pl.title || pl.id;
      els.ytPlaylist.appendChild(opt);
    }
    if (previous && [...els.ytPlaylist.options].some((o) => o.value === previous)) {
      els.ytPlaylist.value = previous;
    }
  }

  async function ensureYoutubePlaylists(force) {
    if (!els.ytPlaylist) {
      return;
    }
    if (youtubePlaylistsLoading) {
      return;
    }
    if (youtubePlaylistsLoaded && !force) {
      return;
    }
    youtubePlaylistsLoading = true;
    setYtPlaylistStatus("Loading playlists…");
    try {
      const res = await fetch("/api/marketing/youtube/playlists");
      const data = await res.json();
      if (!res.ok || !data.ok) {
        const err = data.error || {};
        const code = err.code || `http_${res.status}`;
        const message = err.message || code;
        youtubePlaylists = [];
        youtubePlaylistsLoaded = false;
        fillYoutubePlaylistSelect("");
        let hint = message;
        if (code === "missing_youtube_credentials" || code === "youtube_reauth_required") {
          hint =
            "YouTube credentials missing or refresh expired — run youtube_oauth_get_refresh_token.py (Brand Account).";
        }
        setYtPlaylistStatus(hint, true);
        return;
      }
      const list = (data.data && data.data.playlists) || [];
      youtubePlaylists = Array.isArray(list)
        ? list.filter((p) => p && p.id).map((p) => ({ id: String(p.id), title: String(p.title || p.id) }))
        : [];
      youtubePlaylistsLoaded = true;
      fillYoutubePlaylistSelect();
      setYtPlaylistStatus(
        youtubePlaylists.length
          ? `${youtubePlaylists.length} playlist(s)`
          : "No playlists on this channel."
      );
    } catch (err) {
      youtubePlaylists = [];
      youtubePlaylistsLoaded = false;
      fillYoutubePlaylistSelect("");
      setYtPlaylistStatus(`Could not load playlists: ${err.message || err}`, true);
    } finally {
      youtubePlaylistsLoading = false;
    }
  }

  function syncPlatformScheduleExtras() {
    if (els.fbLinkWrap) {
      els.fbLinkWrap.hidden = els.fbType?.value !== "link";
    }
    if (els.fbScheduleWrap) {
      els.fbScheduleWrap.hidden = !els.fbScheduleLater?.checked;
    }
    if (els.ytScheduleWrap) {
      els.ytScheduleWrap.hidden = !els.ytScheduleLater?.checked;
    }
    if (els.ttScheduleWrap) {
      els.ttScheduleWrap.hidden = !els.ttScheduleLater?.checked;
    }
  }

  function renderSelectedHashtags() {
    els.hashtagSelected.replaceChildren();
    for (const tag of selectedHashtags) {
      const chip = document.createElement("span");
      chip.className = "marketing-chip";
      chip.appendChild(document.createTextNode(tag));
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "marketing-chip-remove";
      remove.title = "Remove";
      remove.setAttribute("aria-label", `Remove ${tag}`);
      remove.textContent = "×";
      remove.addEventListener("click", () => {
        selectedHashtags = selectedHashtags.filter((t) => t !== tag);
        renderSelectedHashtags();
      });
      chip.appendChild(remove);
      els.hashtagSelected.appendChild(chip);
    }
  }

  function rememberHashtag(tag) {
    if (!hashtagLibrary.includes(tag)) {
      hashtagLibrary = [tag, ...hashtagLibrary].slice(0, 80);
      saveLocalJson(HASH_KEY, hashtagLibrary);
      renderHashtagLibrary();
    }
  }

  function addHashtag(raw) {
    const tag = normalizeHashtag(raw);
    if (!tag) {
      return;
    }
    if (!selectedHashtags.includes(tag)) {
      selectedHashtags.push(tag);
      renderSelectedHashtags();
    }
    rememberHashtag(tag);
    els.hashtagInput.value = "";
    els.hashtagInput.focus();
  }

  function renderHashtagLibrary() {
    els.hashtagLibrary.replaceChildren();
    if (hashtagLibrary.length === 0) {
      const empty = document.createElement("p");
      empty.className = "marketing-hint";
      empty.textContent = "No saved hashtags yet.";
      els.hashtagLibrary.appendChild(empty);
      return;
    }
    for (const tag of hashtagLibrary) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "marketing-chip";
      btn.textContent = tag;
      btn.title = "Add to this post";
      btn.addEventListener("click", () => addHashtag(tag));
      els.hashtagLibrary.appendChild(btn);
    }
  }

  function appendToDescription(text) {
    const ta = els.description;
    const insert = String(text || "");
    if (!insert) {
      return;
    }
    const start = ta.selectionStart ?? ta.value.length;
    const end = ta.selectionEnd ?? ta.value.length;
    const before = ta.value.slice(0, start);
    const after = ta.value.slice(end);
    const needsSpace =
      before.length > 0 && !/\s$/.test(before) && !/^\s/.test(insert);
    const chunk = (needsSpace ? " " : "") + insert;
    ta.value = before + chunk + after;
    const caret = before.length + chunk.length;
    ta.focus();
    ta.setSelectionRange(caret, caret);
  }

  function renderSnippets() {
    els.snippetList.replaceChildren();
    for (const [index, text] of snippets.entries()) {
      const row = document.createElement("div");
      row.className = "marketing-snippet";
      const insertBtn = document.createElement("button");
      insertBtn.type = "button";
      insertBtn.className = "insert";
      insertBtn.textContent = text;
      insertBtn.title = "Append to description";
      insertBtn.addEventListener("click", () => appendToDescription(text));
      const removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.className = "remove";
      removeBtn.textContent = "×";
      removeBtn.title = "Remove snippet";
      removeBtn.addEventListener("click", () => {
        snippets = snippets.filter((_, i) => i !== index);
        saveLocalJson(SNIPPET_KEY, snippets);
        renderSnippets();
      });
      row.appendChild(insertBtn);
      row.appendChild(removeBtn);
      els.snippetList.appendChild(row);
    }
  }

  function updateMediaHint() {
    const file = els.media.files && els.media.files[0];
    if (!file) {
      els.mediaHint.textContent = "No file selected";
      return;
    }
    const mb = (file.size / (1024 * 1024)).toFixed(2);
    els.mediaHint.textContent = `${file.name} · ${file.type || "unknown"} · ${mb} MB`;
  }

  function setError(msg) {
    els.error.hidden = !msg;
    els.error.textContent = msg || "";
  }

  function setWarn(msg) {
    els.warn.hidden = !msg;
    els.warn.textContent = msg || "";
  }

  function emptyToNull(value) {
    const v = String(value || "").trim();
    return v === "" ? null : v;
  }

  function formatWhen(iso) {
    if (!iso) {
      return "";
    }
    try {
      return new Date(iso).toLocaleString();
    } catch (_err) {
      return String(iso);
    }
  }

  const INSIGHT_LABELS = {
    post_impressions: "Impressions",
    post_impressions_unique: "Reach (unique)",
    post_impressions_paid: "Impressions (paid)",
    post_impressions_paid_unique: "Reach paid (unique)",
    post_impressions_fan: "Impressions (followers)",
    post_impressions_fan_unique: "Reach followers (unique)",
    post_impressions_organic: "Impressions (organic)",
    post_impressions_organic_unique: "Reach organic (unique)",
    post_impressions_viral: "Impressions (viral)",
    post_impressions_viral_unique: "Reach viral (unique)",
    post_impressions_nonviral: "Impressions (non-viral)",
    post_impressions_nonviral_unique: "Reach non-viral (unique)",
    post_total_media_view_unique: "Media viewers (unique)",
    post_media_view: "Media views",
    post_clicks: "Clicks",
    post_clicks_by_type: "Clicks by type",
    post_engaged_users: "Engaged users",
    post_activity_by_action_type: "Stories by action",
    post_activity_by_action_type_unique: "People talking (by action)",
    post_reactions_by_type_total: "Reactions by type",
    post_reactions_like_total: "Reactions · Like",
    post_reactions_love_total: "Reactions · Love",
    post_reactions_wow_total: "Reactions · Wow",
    post_reactions_haha_total: "Reactions · Haha",
    post_reactions_sorry_total: "Reactions · Sad",
    post_reactions_anger_total: "Reactions · Anger",
    post_video_views: "Video views (3s+)",
    post_video_views_unique: "Video viewers (unique)",
    post_video_views_organic: "Video views (organic)",
    post_video_views_organic_unique: "Video viewers organic (unique)",
    post_video_views_paid: "Video views (paid)",
    post_video_views_paid_unique: "Video viewers paid (unique)",
    post_video_views_autoplayed: "Video views (autoplay)",
    post_video_views_clicked_to_play: "Video views (click-to-play)",
    post_video_views_15s: "Video views (15s+)",
    post_video_avg_time_watched: "Avg watch time (ms)",
    post_video_view_time: "Total watch time (ms)",
    post_video_view_time_organic: "Watch time organic (ms)",
    post_video_complete_views_organic: "Near-complete views (organic)",
    post_video_complete_views_organic_unique: "Near-complete viewers (organic)",
    post_video_complete_views_paid: "Near-complete views (paid)",
    post_video_complete_views_paid_unique: "Near-complete viewers (paid)",
    post_video_complete_views_30s_unique: "30s+ viewers (unique)",
    post_video_complete_views_30s_autoplayed: "30s+ views (autoplay)",
    post_video_complete_views_30s_clicked_to_play: "30s+ views (click-to-play)",
    post_video_complete_views_30s_organic: "30s+ views (organic)",
    post_video_complete_views_30s_paid: "30s+ views (paid)",
    post_video_length: "Video length (ms)",
    post_video_social_actions_count_unique: "Video social actions (unique)",
    post_video_views_by_distribution_type: "Video views by distribution",
    post_video_view_time_by_distribution_type: "Watch time by distribution",
  };

  const INSIGHT_SECTIONS = [
    {
      title: "Reach & impressions",
      keys: [
        "post_impressions",
        "post_impressions_unique",
        "post_total_media_view_unique",
        "post_media_view",
        "post_impressions_organic",
        "post_impressions_organic_unique",
        "post_impressions_paid",
        "post_impressions_paid_unique",
        "post_impressions_fan",
        "post_impressions_fan_unique",
        "post_impressions_viral",
        "post_impressions_viral_unique",
        "post_impressions_nonviral",
        "post_impressions_nonviral_unique",
      ],
    },
    {
      title: "Clicks & activity",
      keys: [
        "post_clicks",
        "post_clicks_by_type",
        "post_engaged_users",
        "post_activity_by_action_type",
        "post_activity_by_action_type_unique",
      ],
    },
    {
      title: "Reactions (Insights)",
      keys: [
        "post_reactions_by_type_total",
        "post_reactions_like_total",
        "post_reactions_love_total",
        "post_reactions_wow_total",
        "post_reactions_haha_total",
        "post_reactions_sorry_total",
        "post_reactions_anger_total",
      ],
    },
    {
      title: "Video",
      keys: [
        "post_video_views",
        "post_video_views_unique",
        "post_video_views_organic",
        "post_video_views_organic_unique",
        "post_video_views_paid",
        "post_video_views_paid_unique",
        "post_video_views_autoplayed",
        "post_video_views_clicked_to_play",
        "post_video_views_15s",
        "post_video_avg_time_watched",
        "post_video_view_time",
        "post_video_view_time_organic",
        "post_video_complete_views_organic",
        "post_video_complete_views_organic_unique",
        "post_video_complete_views_paid",
        "post_video_complete_views_paid_unique",
        "post_video_complete_views_30s_unique",
        "post_video_complete_views_30s_autoplayed",
        "post_video_complete_views_30s_clicked_to_play",
        "post_video_complete_views_30s_organic",
        "post_video_complete_views_30s_paid",
        "post_video_length",
        "post_video_social_actions_count_unique",
        "post_video_views_by_distribution_type",
        "post_video_view_time_by_distribution_type",
      ],
    },
  ];

  function formatMetricValue(value) {
    if (value === null || value === undefined) {
      return "—";
    }
    if (typeof value === "number") {
      return value.toLocaleString();
    }
    if (typeof value === "object") {
      return Object.entries(value)
        .map(([k, v]) => `${k}: ${typeof v === "number" ? v.toLocaleString() : v}`)
        .join(", ");
    }
    return String(value);
  }

  function insightLabel(key, titles) {
    if (titles && titles[key]) {
      return titles[key];
    }
    if (INSIGHT_LABELS[key]) {
      return INSIGHT_LABELS[key];
    }
    return key
      .replace(/^post_/, "")
      .replace(/_/g, " ")
      .replace(/\b\w/g, (c) => c.toUpperCase());
  }

  function appendMetricRow(dl, label, value) {
    const dt = document.createElement("dt");
    dt.textContent = label;
    const dd = document.createElement("dd");
    dd.textContent = formatMetricValue(value);
    dl.appendChild(dt);
    dl.appendChild(dd);
  }

  function appendMetricSection(dl, title) {
    const dt = document.createElement("dt");
    dt.className = "marketing-metrics-section";
    dt.textContent = title;
    const dd = document.createElement("dd");
    dd.className = "marketing-metrics-section-spacer";
    dd.textContent = "";
    dl.appendChild(dt);
    dl.appendChild(dd);
  }

  function clearFacebookMetrics(targets) {
    const t = targets || {
      grid: els.metricsFacebook,
      dl: els.metricsFacebookDl,
      warn: els.metricsFacebookWarn,
    };
    if (t.dl) {
      t.dl.replaceChildren();
    }
    if (t.grid) {
      t.grid.hidden = true;
    }
    if (t.warn) {
      t.warn.hidden = true;
      t.warn.textContent = "";
    }
  }

  function renderFacebookMetrics(metrics, targets) {
    const t = targets || {
      grid: els.metricsFacebook,
      dl: els.metricsFacebookDl,
      warn: els.metricsFacebookWarn,
    };
    clearFacebookMetrics(t);
    if (!t.grid || !t.dl || !metrics) {
      return;
    }
    t.grid.hidden = false;
    const eng = metrics.engagement || {};
    appendMetricSection(t.dl, "Engagement (live)");
    appendMetricRow(t.dl, "Reactions", eng.reactions);
    appendMetricRow(t.dl, "Likes", eng.likes);
    appendMetricRow(t.dl, "Comments", eng.comments);
    appendMetricRow(t.dl, "Shares", eng.shares);

    const insights =
      metrics.insights && typeof metrics.insights === "object"
        ? metrics.insights
        : {};
    const titles =
      metrics.insight_titles && typeof metrics.insight_titles === "object"
        ? metrics.insight_titles
        : {};
    const shown = new Set();

    for (const section of INSIGHT_SECTIONS) {
      const present = section.keys.filter(
        (key) => insights[key] !== undefined && insights[key] !== null
      );
      if (!present.length) {
        continue;
      }
      appendMetricSection(t.dl, section.title);
      for (const key of present) {
        appendMetricRow(t.dl, insightLabel(key, titles), insights[key]);
        shown.add(key);
      }
    }

    const extras = Object.keys(insights).filter(
      (key) => !shown.has(key) && insights[key] !== undefined && insights[key] !== null
    );
    if (extras.length) {
      appendMetricSection(t.dl, "Other Insights");
      extras.sort();
      for (const key of extras) {
        appendMetricRow(t.dl, insightLabel(key, titles), insights[key]);
      }
    }

    appendMetricSection(t.dl, "Meta");
    if (metrics.permalink_url) {
      appendMetricRow(t.dl, "Link", metrics.permalink_url);
    }
    if (metrics.insights_object_id) {
      appendMetricRow(t.dl, "Insights object", metrics.insights_object_id);
    }
    if (metrics.fetched_at) {
      appendMetricRow(t.dl, "Fetched", formatWhen(metrics.fetched_at));
    }

    const warnings = Array.isArray(metrics.warnings) ? metrics.warnings : [];
    if (warnings.length && t.warn) {
      t.warn.hidden = false;
      t.warn.textContent = warnings.join(" · ");
    }
  }

  async function loadFacebookMetrics(postId) {
    if (!els.metrics || !els.metricsStatus) {
      return;
    }
    els.metricsStatus.hidden = false;
    els.metricsStatus.textContent = "Loading Facebook metrics…";
    els.metricsStatus.classList.remove("marketing-hint-error");
    try {
      const res = await fetch(
        `/api/marketing/posts/${encodeURIComponent(postId)}/metrics/facebook`
      );
      const data = await res.json();
      if (!data.ok) {
        const msg =
          (data.error && data.error.message) ||
          data.error ||
          `HTTP ${res.status}`;
        throw new Error(msg);
      }
      renderFacebookMetrics(data.metrics || {});
      els.metricsStatus.hidden = true;
      els.metricsStatus.textContent = "";
    } catch (err) {
      clearFacebookMetrics();
      els.metricsStatus.hidden = false;
      els.metricsStatus.classList.add("marketing-hint-error");
      els.metricsStatus.textContent = `Facebook metrics: ${err.message || err}`;
    }
  }

  async function loadFacebookMetricsByObjectId(objectId) {
    const statusEl = els.platformMetricsStatus;
    const targets = {
      grid: els.platformMetricsFacebook,
      dl: els.platformMetricsFacebookDl,
      warn: els.platformMetricsFacebookWarn,
    };
    if (!statusEl) {
      return;
    }
    statusEl.hidden = false;
    statusEl.textContent = "Loading Facebook metrics…";
    statusEl.classList.remove("marketing-hint-error");
    try {
      const res = await fetch(
        `/api/marketing/metrics/facebook?object_id=${encodeURIComponent(objectId)}`
      );
      const data = await res.json();
      if (!data.ok) {
        const msg =
          (data.error && data.error.message) ||
          data.error ||
          `HTTP ${res.status}`;
        throw new Error(msg);
      }
      renderFacebookMetrics(data.metrics || {}, targets);
      statusEl.hidden = true;
      statusEl.textContent = "";
    } catch (err) {
      clearFacebookMetrics(targets);
      statusEl.hidden = false;
      statusEl.classList.add("marketing-hint-error");
      statusEl.textContent = `Facebook metrics: ${err.message || err}`;
    }
  }

  const YT_INSIGHT_LABELS = {
    viewCount: "Views",
    likeCount: "Likes",
    commentCount: "Comments",
    favoriteCount: "Favorites",
    duration: "Duration (ISO)",
    definition: "Definition",
    privacyStatus: "Privacy",
    madeForKids: "Made for kids",
    publishedAt: "Published",
    channelTitle: "Channel",
    categoryId: "Category id",
  };

  function clearYouTubeMetrics(targets) {
    const t = targets || {
      grid: els.metricsYoutube,
      dl: els.metricsYoutubeDl,
      warn: els.metricsYoutubeWarn,
    };
    if (t.dl) {
      t.dl.replaceChildren();
    }
    if (t.grid) {
      t.grid.hidden = true;
    }
    if (t.warn) {
      t.warn.hidden = true;
      t.warn.textContent = "";
    }
  }

  function renderYouTubeMetrics(metrics, targets) {
    const t = targets || {
      grid: els.metricsYoutube,
      dl: els.metricsYoutubeDl,
      warn: els.metricsYoutubeWarn,
    };
    clearYouTubeMetrics(t);
    if (!t.grid || !t.dl || !metrics) {
      return;
    }
    t.grid.hidden = false;
    const eng = metrics.engagement || {};
    appendMetricSection(t.dl, "Statistics");
    appendMetricRow(t.dl, "Views", eng.views);
    appendMetricRow(t.dl, "Likes", eng.likes);
    appendMetricRow(t.dl, "Comments", eng.comments);
    appendMetricRow(t.dl, "Favorites", eng.favorites);

    const insights =
      metrics.insights && typeof metrics.insights === "object"
        ? metrics.insights
        : {};
    const skip = new Set(["viewCount", "likeCount", "commentCount", "favoriteCount"]);
    const extraKeys = Object.keys(insights).filter(
      (k) => !skip.has(k) && insights[k] !== undefined && insights[k] !== null
    );
    if (extraKeys.length) {
      appendMetricSection(t.dl, "Details");
      for (const key of extraKeys) {
        const label = YT_INSIGHT_LABELS[key] || key;
        let value = insights[key];
        if (key === "publishedAt") {
          value = formatWhen(value);
        }
        appendMetricRow(t.dl, label, value);
      }
    }

    appendMetricSection(t.dl, "Meta");
    if (metrics.title) {
      appendMetricRow(t.dl, "Title", metrics.title);
    }
    if (metrics.permalink_url) {
      appendMetricRow(t.dl, "Link", metrics.permalink_url);
    }
    if (metrics.object_id) {
      appendMetricRow(t.dl, "Video id", metrics.object_id);
    }
    if (metrics.fetched_at) {
      appendMetricRow(t.dl, "Fetched", formatWhen(metrics.fetched_at));
    }

    const warnings = Array.isArray(metrics.warnings) ? metrics.warnings : [];
    if (warnings.length && t.warn) {
      t.warn.hidden = false;
      t.warn.textContent = warnings.join(" · ");
    }
  }

  async function loadYouTubeMetrics(postId) {
    const targets = {
      grid: els.metricsYoutube,
      dl: els.metricsYoutubeDl,
      warn: els.metricsYoutubeWarn,
    };
    if (!els.metricsStatus) {
      return;
    }
    els.metricsStatus.hidden = false;
    els.metricsStatus.textContent = "Loading YouTube metrics…";
    els.metricsStatus.classList.remove("marketing-hint-error");
    try {
      const res = await fetch(
        `/api/marketing/posts/${encodeURIComponent(postId)}/metrics/youtube`
      );
      const data = await res.json();
      if (!data.ok) {
        const msg =
          (data.error && data.error.message) ||
          data.error ||
          `HTTP ${res.status}`;
        throw new Error(msg);
      }
      renderYouTubeMetrics(data.metrics || {}, targets);
      els.metricsStatus.hidden = true;
      els.metricsStatus.textContent = "";
    } catch (err) {
      clearYouTubeMetrics(targets);
      els.metricsStatus.hidden = false;
      els.metricsStatus.classList.add("marketing-hint-error");
      els.metricsStatus.textContent = `YouTube metrics: ${err.message || err}`;
    }
  }

  async function loadYouTubeMetricsByObjectId(objectId) {
    const statusEl = els.platformMetricsStatus;
    const targets = {
      grid: els.platformMetricsYoutube,
      dl: els.platformMetricsYoutubeDl,
      warn: els.platformMetricsYoutubeWarn,
    };
    if (!statusEl) {
      return;
    }
    statusEl.hidden = false;
    statusEl.textContent = "Loading YouTube metrics…";
    statusEl.classList.remove("marketing-hint-error");
    try {
      const res = await fetch(
        `/api/marketing/metrics/youtube?object_id=${encodeURIComponent(objectId)}`
      );
      const data = await res.json();
      if (!data.ok) {
        const msg =
          (data.error && data.error.message) ||
          data.error ||
          `HTTP ${res.status}`;
        throw new Error(msg);
      }
      renderYouTubeMetrics(data.metrics || {}, targets);
      statusEl.hidden = true;
      statusEl.textContent = "";
    } catch (err) {
      clearYouTubeMetrics(targets);
      statusEl.hidden = false;
      statusEl.classList.add("marketing-hint-error");
      statusEl.textContent = `YouTube metrics: ${err.message || err}`;
    }
  }

  function setupMetricsForPost(post) {
    activeDetailPostId = String(post.id || "");
    const publish = post.publish && typeof post.publish === "object" ? post.publish : {};
    const results =
      publish.results && typeof publish.results === "object" ? publish.results : {};
    const fb = results.facebook;
    const yt = results.youtube;
    activeDetailHasFb = Boolean(
      fb &&
        fb.ok &&
        fb.data &&
        (fb.data.id || fb.data.publish_id)
    );
    activeDetailHasYt = Boolean(
      yt &&
        yt.ok &&
        yt.data &&
        (yt.data.id || yt.data.video_id)
    );

    if (!els.metrics) {
      return;
    }
    clearFacebookMetrics();
    clearYouTubeMetrics();
    if (!activeDetailHasFb && !activeDetailHasYt) {
      els.metrics.hidden = true;
      if (els.metricsStatus) {
        els.metricsStatus.hidden = true;
      }
      return;
    }
    els.metrics.hidden = false;
    if (els.metricsStatus) {
      els.metricsStatus.hidden = true;
      els.metricsStatus.textContent = "";
    }
    if (activeDetailHasFb) {
      loadFacebookMetrics(activeDetailPostId);
    }
    if (activeDetailHasYt) {
      loadYouTubeMetrics(activeDetailPostId);
    }
  }

  const PLATFORM_PAGE_SIZE = 5;

  function clearPlatformMetricsPanel() {
    clearFacebookMetrics({
      grid: els.platformMetricsFacebook,
      dl: els.platformMetricsFacebookDl,
      warn: els.platformMetricsFacebookWarn,
    });
    clearYouTubeMetrics({
      grid: els.platformMetricsYoutube,
      dl: els.platformMetricsYoutubeDl,
      warn: els.platformMetricsYoutubeWarn,
    });
    if (els.platformMetricsStatus) {
      els.platformMetricsStatus.hidden = true;
      els.platformMetricsStatus.textContent = "";
      els.platformMetricsStatus.classList.remove("marketing-hint-error");
    }
  }

  function renderPlatformList() {
    if (!els.platformList || !els.platformEmpty) {
      return;
    }
    els.platformList.replaceChildren();
    els.platformEmpty.hidden = platformPosts.length > 0;
    for (const post of platformPosts) {
      const li = document.createElement("li");
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "marketing-post-link";
      btn.dataset.objectId = String(post.id || "");
      const title = document.createElement("span");
      title.className = "title";
      title.textContent = post.title || "(untitled)";
      const meta = document.createElement("span");
      meta.className = "meta";
      meta.textContent = [
        post.platform || activePlatformName,
        post.kind || "",
        formatWhen(post.created_time),
      ]
        .filter(Boolean)
        .join(" · ");
      btn.appendChild(title);
      btn.appendChild(meta);
      btn.addEventListener("click", () => openPlatformDetail(post));
      li.appendChild(btn);
      els.platformList.appendChild(li);
    }
    if (els.platformMoreWrap) {
      els.platformMoreWrap.hidden = !platformCursor;
    }
  }

  async function loadPlatformPosts({ reset = false, append = false } = {}) {
    if (!els.platformStatus || !els.platformFilter) {
      return;
    }
    const platform = els.platformFilter.value || "facebook";
    activePlatformName = platform;
    if (reset) {
      platformPosts = [];
      platformCursor = null;
      activePlatformObjectId = null;
      renderPlatformList();
    }
    els.platformStatus.hidden = false;
    els.platformStatus.classList.remove("marketing-hint-error");
    els.platformStatus.textContent = append
      ? `Loading ${PLATFORM_PAGE_SIZE} more…`
      : `Loading latest ${PLATFORM_PAGE_SIZE} posts…`;
    try {
      const params = new URLSearchParams({
        platform,
        limit: String(PLATFORM_PAGE_SIZE),
      });
      if (append && platformCursor) {
        params.set("after", platformCursor);
      }
      const res = await fetch(`/api/marketing/platform-posts?${params}`);
      const data = await res.json();
      if (!data.ok) {
        const msg =
          (data.error && data.error.message) ||
          data.error ||
          `HTTP ${res.status}`;
        throw new Error(msg);
      }
      const batch = Array.isArray(data.posts) ? data.posts : [];
      platformPosts = append ? platformPosts.concat(batch) : batch;
      platformCursor =
        data.paging && data.paging.has_more ? data.paging.after || null : null;
      renderPlatformList();
      const shown = platformPosts.length;
      els.platformStatus.hidden = false;
      els.platformStatus.classList.remove("marketing-hint-error");
      els.platformStatus.textContent = platformCursor
        ? `Showing ${shown} · Load more for older posts`
        : shown
          ? `Showing ${shown}`
          : "";
      if (!shown) {
        els.platformStatus.hidden = true;
      }
    } catch (err) {
      if (!append) {
        platformPosts = [];
        platformCursor = null;
        renderPlatformList();
      }
      els.platformStatus.hidden = false;
      els.platformStatus.classList.add("marketing-hint-error");
      els.platformStatus.textContent = `Could not load posts: ${err.message || err}`;
    }
  }

  function openPlatformDetail(post) {
    activePlatformObjectId = String(post.id || "");
    activePlatformName = String(post.platform || activePlatformName || "facebook");
    if (els.platformDetailTitle) {
      els.platformDetailTitle.textContent = post.title || "(untitled)";
    }
    if (els.platformDetailMeta) {
      els.platformDetailMeta.textContent = [
        activePlatformName,
        post.kind || "",
        formatWhen(post.created_time),
        post.permalink_url || "",
      ]
        .filter(Boolean)
        .join(" · ");
    }
    if (els.platformDetailJson) {
      els.platformDetailJson.textContent = JSON.stringify(post, null, 2);
    }
    clearPlatformMetricsPanel();
    showScreen("platform-detail");
    // Metrics + Insights load only on this detail screen (never on the list).
    if (activePlatformName === "facebook" && activePlatformObjectId) {
      loadFacebookMetricsByObjectId(activePlatformObjectId);
    } else if (activePlatformName === "youtube" && activePlatformObjectId) {
      loadYouTubeMetricsByObjectId(activePlatformObjectId);
    } else if (els.platformMetricsStatus) {
      els.platformMetricsStatus.hidden = false;
      els.platformMetricsStatus.classList.remove("marketing-hint-error");
      els.platformMetricsStatus.textContent =
        "Metrics for this platform are not wired yet.";
    }
  }

  function renderPostList() {
    els.postList.replaceChildren();
    els.listEmpty.hidden = postSummaries.length > 0;
    for (const post of postSummaries) {
      const li = document.createElement("li");
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "marketing-post-link";
      btn.dataset.postId = String(post.id || "");
      const title = document.createElement("span");
      title.className = "title";
      title.textContent = post.title || "(untitled)";
      const meta = document.createElement("span");
      meta.className = "meta";
      const platforms = Array.isArray(post.platforms)
        ? post.platforms.join(", ")
        : "";
      meta.textContent = [platforms, formatWhen(post.created_at)]
        .filter(Boolean)
        .join(" · ");
      if (post.publish_ok === true) {
        meta.textContent += " · published";
      } else if (post.publish_ok === false) {
        meta.textContent += " · publish failed";
      }
      btn.appendChild(title);
      btn.appendChild(meta);
      btn.addEventListener("click", () => openPostDetail(String(post.id)));
      li.appendChild(btn);
      els.postList.appendChild(li);
    }
  }

  async function loadPosts() {
    els.listStatus.hidden = true;
    try {
      const res = await fetch("/api/marketing/posts");
      const data = await res.json();
      if (!data.ok) {
        throw new Error(data.error || "load_failed");
      }
      postSummaries = Array.isArray(data.posts) ? data.posts : [];
      renderPostList();
    } catch (err) {
      els.listStatus.hidden = false;
      els.listStatus.textContent = `Could not load posts: ${err.message || err}`;
      postSummaries = [];
      renderPostList();
    }
  }

  async function openPostDetail(postId) {
    try {
      const res = await fetch(`/api/marketing/posts/${encodeURIComponent(postId)}`);
      const data = await res.json();
      if (!data.ok || !data.post) {
        throw new Error(data.error || "not_found");
      }
      const post = data.post;
      els.detailTitle.textContent = post.title || "(untitled)";
      const platforms = Array.isArray(post.platforms)
        ? post.platforms.join(", ")
        : "";
      els.detailMeta.textContent = [platforms, formatWhen(post.created_at)]
        .filter(Boolean)
        .join(" · ");
      els.detailJson.textContent = JSON.stringify(post, null, 2);
      setupMetricsForPost(post);
      showScreen("detail");
    } catch (err) {
      els.listStatus.hidden = false;
      els.listStatus.textContent = `Could not open post: ${err.message || err}`;
      setMarketingTab("saved");
    }
  }

  function resetComposeForm() {
    form.reset();
    selectedHashtags = [];
    renderSelectedHashtags();
    syncPlatformPanels();
    syncPlatformScheduleExtras();
    updateMediaHint();
    setError("");
    setWarn("");
    els.preview.hidden = true;
    els.previewJson.textContent = "";
  }

  function openCompose() {
    resetComposeForm();
    showScreen("compose");
    els.title.focus();
  }

  function buildPayload() {
    const platforms = selectedPlatforms();
    const file = els.media.files && els.media.files[0];
    const payload = {
      platforms,
      title: els.title.value.trim(),
      description: els.description.value,
      hashtags: selectedHashtags.slice(),
      media: file
        ? { name: file.name, type: file.type || "", size: file.size }
        : null,
    };

    if (platforms.includes("facebook")) {
      const scheduleLater = Boolean(els.fbScheduleLater?.checked);
      payload.facebook = {
        post_type: els.fbType.value,
        link:
          els.fbType.value === "link"
            ? document.getElementById("mkt-fb-link").value.trim()
            : "",
        schedule_at: scheduleLater
          ? emptyToNull(document.getElementById("mkt-fb-schedule").value)
          : null,
        publish_mode: scheduleLater ? "schedule" : "now",
      };
    }

    if (platforms.includes("youtube")) {
      const scheduleLater = Boolean(els.ytScheduleLater?.checked);
      payload.youtube = {
        privacy: document.getElementById("mkt-yt-privacy").value,
        tags: selectedHashtags.map((t) => t.replace(/^#/, "")),
        publish_at: scheduleLater
          ? emptyToNull(document.getElementById("mkt-yt-publish-at").value)
          : null,
        playlist_id: emptyToNull(
          document.getElementById("mkt-yt-playlist")?.value || ""
        ),
        playlist_title: (() => {
          const sel = document.getElementById("mkt-yt-playlist");
          if (!sel || !sel.value) {
            return null;
          }
          const opt = sel.selectedOptions && sel.selectedOptions[0];
          return opt ? opt.textContent : null;
        })(),
      };
    }

    if (platforms.includes("tiktok")) {
      const scheduleLater = Boolean(els.ttScheduleLater?.checked);
      payload.tiktok = {
        privacy_level: document.getElementById("mkt-tt-privacy").value,
        disable_comment: document.getElementById("mkt-tt-disable-comment")
          .checked,
        disable_duet: document.getElementById("mkt-tt-disable-duet").checked,
        disable_stitch: document.getElementById("mkt-tt-disable-stitch")
          .checked,
        schedule_at: scheduleLater
          ? emptyToNull(document.getElementById("mkt-tt-schedule").value)
          : null,
      };
    }

    return payload;
  }

  function validate(payload) {
    if (!payload.platforms.length) {
      return "Select at least one platform.";
    }
    if (!payload.title) {
      return "Title is required.";
    }
    if (payload.facebook?.post_type === "link" && !payload.facebook.link) {
      return "Facebook link posts require a Link URL.";
    }
    if (
      payload.facebook?.publish_mode === "schedule" &&
      !payload.facebook.schedule_at
    ) {
      return "Facebook schedule requires a date/time.";
    }
    if (
      els.ytScheduleLater?.checked &&
      payload.platforms.includes("youtube") &&
      !payload.youtube?.publish_at
    ) {
      return "YouTube schedule requires a date/time.";
    }
    if (
      els.ttScheduleLater?.checked &&
      payload.platforms.includes("tiktok") &&
      !payload.tiktok?.schedule_at
    ) {
      return "TikTok schedule requires a date/time.";
    }
    return "";
  }

  function mediaRequiredError(payload) {
    const needsMedia =
      payload.platforms.includes("youtube") ||
      payload.platforms.includes("tiktok");
    if (needsMedia && !(els.media.files && els.media.files[0])) {
      return "YouTube/TikTok require a video file before publish.";
    }
    return "";
  }

  function formatPublishSummary(publish) {
    if (!publish || !publish.results) {
      return "";
    }
    const lines = [];
    for (const [platform, result] of Object.entries(publish.results)) {
      if (result && result.ok) {
        const id =
          (result.data && (result.data.id || result.data.publish_id)) || "ok";
        const warn = result.warning ? ` (warn: ${result.warning})` : "";
        lines.push(`${platform}: ok — ${id}${warn}`);
      } else {
        const err =
          (result && result.error && result.error.message) ||
          (result && result.error && result.error.code) ||
          "failed";
        lines.push(`${platform}: failed — ${err}`);
      }
    }
    return lines.join("\n");
  }

  form.addEventListener("change", (event) => {
    const t = event.target;
    if (t && t.name === "platform") {
      syncPlatformPanels();
    }
    if (
      t === els.fbType ||
      t === els.fbScheduleLater ||
      t === els.ytScheduleLater ||
      t === els.ttScheduleLater
    ) {
      syncPlatformScheduleExtras();
    }
    if (t === els.media) {
      updateMediaHint();
    }
  });

  if (els.ytPlaylistRefresh) {
    els.ytPlaylistRefresh.addEventListener("click", () => {
      ensureYoutubePlaylists(true);
    });
  }

  els.hashtagAdd.addEventListener("click", () => {
    addHashtag(els.hashtagInput.value);
  });

  els.hashtagInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      addHashtag(els.hashtagInput.value);
    }
  });

  els.snippetAdd.addEventListener("click", () => {
    const text = els.snippetInput.value.trim();
    if (!text) {
      return;
    }
    if (!snippets.includes(text)) {
      snippets = [text, ...snippets].slice(0, 40);
      saveLocalJson(SNIPPET_KEY, snippets);
      renderSnippets();
    }
    els.snippetInput.value = "";
  });

  els.snippetInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      els.snippetAdd.click();
    }
  });

  els.createNew.addEventListener("click", () => openCompose());
  els.composeBack.addEventListener("click", () => {
    setMarketingTab(activeMktTab);
  });
  els.detailBack.addEventListener("click", () => {
    setMarketingTab("saved");
  });
  if (els.metricsRefresh) {
    els.metricsRefresh.addEventListener("click", () => {
      if (!activeDetailPostId) {
        return;
      }
      if (activeDetailHasFb) {
        loadFacebookMetrics(activeDetailPostId);
      }
      if (activeDetailHasYt) {
        loadYouTubeMetrics(activeDetailPostId);
      }
    });
  }
  if (els.subtabs) {
    els.subtabs.addEventListener("click", (event) => {
      const btn = event.target.closest(".marketing-subtab");
      if (!btn || !els.subtabs.contains(btn)) {
        return;
      }
      const tab = btn.dataset.mktTab;
      if (tab) {
        setMarketingTab(tab);
      }
    });
  }
  if (els.platformRefresh) {
    els.platformRefresh.addEventListener("click", () => {
      loadPlatformPosts({ reset: true });
    });
  }
  if (els.platformFilter) {
    els.platformFilter.addEventListener("change", () => {
      loadPlatformPosts({ reset: true });
    });
  }
  if (els.platformMore) {
    els.platformMore.addEventListener("click", () => {
      loadPlatformPosts({ append: true });
    });
  }
  if (els.platformDetailBack) {
    els.platformDetailBack.addEventListener("click", () => {
      setMarketingTab("platform");
    });
  }
  if (els.platformMetricsRefresh) {
    els.platformMetricsRefresh.addEventListener("click", () => {
      if (!activePlatformObjectId) {
        return;
      }
      if (activePlatformName === "facebook") {
        loadFacebookMetricsByObjectId(activePlatformObjectId);
      } else if (activePlatformName === "youtube") {
        loadYouTubeMetricsByObjectId(activePlatformObjectId);
      }
    });
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    setError("");
    setWarn("");
    const payload = buildPayload();
    const err = validate(payload) || mediaRequiredError(payload);
    if (err) {
      els.preview.hidden = true;
      setError(err);
      return;
    }
    els.previewJson.textContent = JSON.stringify(payload, null, 2);
    els.preview.hidden = false;

    const submitBtn = document.getElementById("mkt-submit");
    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.textContent = "Publishing…";
    }

    try {
      const fd = new FormData();
      fd.append("payload", JSON.stringify(payload));
      const file = els.media.files && els.media.files[0];
      if (file) {
        fd.append("media", file, file.name);
      }
      const res = await fetch("/api/marketing/posts", {
        method: "POST",
        body: fd,
      });
      const data = await res.json();
      const summary = formatPublishSummary(data.publish);
      if (summary) {
        els.previewJson.textContent = summary;
        els.preview.hidden = false;
      }
      if (!data.ok) {
        const msg =
          (data.error && data.error.message) ||
          summary ||
          `publish_failed_${res.status}`;
        setError(msg);
        if (summary) {
          setWarn(summary);
        }
        await loadPosts();
        return;
      }
      setWarn(summary || "Published.");
      await loadPosts();
      setMarketingTab("saved");
    } catch (saveErr) {
      setError(`Could not publish: ${saveErr.message || saveErr}`);
    } finally {
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.textContent = "Publish";
      }
    }
  });

  syncPlatformPanels();
  syncPlatformScheduleExtras();
  updateMediaHint();
  renderSelectedHashtags();
  renderHashtagLibrary();
  renderSnippets();
  showScreen("landing");
  loadPosts();
})();
