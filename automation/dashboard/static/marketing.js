(() => {
  const HASH_KEY = "wf_dash_marketing_hashtags";
  const SNIPPET_KEY = "wf_dash_marketing_snippets";
  const DEFAULT_SNIPPETS = ["URL", "CTA", "https://"];

  const form = document.getElementById("mkt-form");
  const landing = document.getElementById("mkt-landing");
  const compose = document.getElementById("mkt-compose");
  const detail = document.getElementById("mkt-detail");
  if (!form || !landing || !compose || !detail) {
    return;
  }

  const els = {
    createNew: document.getElementById("mkt-create-new"),
    composeBack: document.getElementById("mkt-compose-back"),
    detailBack: document.getElementById("mkt-detail-back"),
    postList: document.getElementById("mkt-post-list"),
    listEmpty: document.getElementById("mkt-list-empty"),
    listStatus: document.getElementById("mkt-list-status"),
    detailTitle: document.getElementById("mkt-detail-title"),
    detailMeta: document.getElementById("mkt-detail-meta"),
    detailJson: document.getElementById("mkt-detail-json"),
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
      showScreen("detail");
    } catch (err) {
      els.listStatus.hidden = false;
      els.listStatus.textContent = `Could not open post: ${err.message || err}`;
      showScreen("landing");
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
    showScreen("landing");
    loadPosts();
  });
  els.detailBack.addEventListener("click", () => {
    showScreen("landing");
    loadPosts();
  });

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
      showScreen("landing");
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
