(() => {
  const kindEl = document.getElementById("rev-kind");
  const fromEl = document.getElementById("rev-from");
  const toEl = document.getElementById("rev-to");
  const refreshBtn = document.getElementById("rev-refresh");
  const statusEl = document.getElementById("rev-status");
  const warnEl = document.getElementById("rev-warn");
  const summaryEl = document.getElementById("rev-summary");
  const tbody = document.getElementById("rev-tbody");
  const subtabs = document.getElementById("rev-subtabs");
  const panelRevenue = document.getElementById("rev-panel-revenue");
  const panelDownloads = document.getElementById("rev-panel-downloads");
  const panelExpense = document.getElementById("rev-panel-expense");
  const kpiAlltimeAmounts = document.getElementById("rev-kpi-alltime-amounts");
  const kpiMonthAmounts = document.getElementById("rev-kpi-month-amounts");
  const kpiAlltimeExpenses = document.getElementById("rev-kpi-alltime-expenses");
  const kpiMonthExpenses = document.getElementById("rev-kpi-month-expenses");
  const kpiAlltimeProfit = document.getElementById("rev-kpi-alltime-profit");
  const kpiMonthProfit = document.getElementById("rev-kpi-month-profit");
  const kpiAlltimeMeta = document.getElementById("rev-kpi-alltime-meta");
  const kpiMonthMeta = document.getElementById("rev-kpi-month-meta");
  const expenseForm = document.getElementById("expense-form");
  const expType = document.getElementById("exp-type");
  const expAmount = document.getElementById("exp-amount");
  const expCurrency = document.getElementById("exp-currency");
  const expDescription = document.getElementById("exp-description");
  const expStatus = document.getElementById("exp-status");
  const expTbody = document.getElementById("exp-tbody");
  const dlFromEl = document.getElementById("dl-from");
  const dlToEl = document.getElementById("dl-to");
  const dlRefreshBtn = document.getElementById("dl-refresh");
  const dlStatusEl = document.getElementById("dl-status");
  const dlWarnEl = document.getElementById("dl-warn");
  const dlSummaryEl = document.getElementById("dl-summary");
  const dlTbody = document.getElementById("dl-tbody");
  const dlKpiAlltimeTotal = document.getElementById("dl-kpi-alltime-total");
  const dlKpiAlltimeBySource = document.getElementById("dl-kpi-alltime-by-source");
  const dlKpiMonthTotal = document.getElementById("dl-kpi-month-total");
  const dlKpiMonthBySource = document.getElementById("dl-kpi-month-by-source");
  const dlKpiAlltimeMeta = document.getElementById("dl-kpi-alltime-meta");
  const dlKpiMonthMeta = document.getElementById("dl-kpi-month-meta");

  if (!kindEl || !fromEl || !toEl || !refreshBtn || !summaryEl || !tbody) {
    return;
  }

  let loadedOnce = false;
  let downloadsLoadedOnce = false;
  let loading = false;
  let dlLoading = false;
  let expensesLoaded = false;
  let activeSub = "revenue";
  let persistTimer = null;

  function isoDaysAgo(days) {
    const d = new Date();
    d.setDate(d.getDate() - days);
    return d.toISOString().slice(0, 10);
  }

  function todayIso() {
    return new Date().toISOString().slice(0, 10);
  }

  if (!fromEl.value) fromEl.value = isoDaysAgo(29);
  if (!toEl.value) toEl.value = todayIso();
  if (dlFromEl && !dlFromEl.value) dlFromEl.value = isoDaysAgo(29);
  if (dlToEl && !dlToEl.value) dlToEl.value = todayIso();

  function selectedSources() {
    return Array.from(
      document.querySelectorAll('input[name="rev-source"]:checked')
    ).map((el) => el.value);
  }

  function selectedDownloadSources() {
    return Array.from(
      document.querySelectorAll('input[name="dl-source"]:checked')
    ).map((el) => el.value);
  }

  function setSourceChecks(sources) {
    const set = new Set((sources || []).map(String));
    document.querySelectorAll('input[name="rev-source"]').forEach((el) => {
      el.checked = set.size ? set.has(el.value) : true;
    });
  }

  function setDownloadSourceChecks(sources) {
    const set = new Set((sources || []).map(String));
    document.querySelectorAll('input[name="dl-source"]').forEach((el) => {
      el.checked = set.size ? set.has(el.value) : true;
    });
  }

  function setStatus(text, isError) {
    if (!text) {
      statusEl.hidden = true;
      statusEl.textContent = "";
      return;
    }
    statusEl.hidden = false;
    statusEl.textContent = text;
    statusEl.classList.toggle("revenue-status-error", !!isError);
  }

  function setWarn(text) {
    if (!text) {
      warnEl.hidden = true;
      warnEl.textContent = "";
      return;
    }
    warnEl.hidden = false;
    warnEl.textContent = text;
  }

  function setDlStatus(text, isError) {
    if (!dlStatusEl) return;
    if (!text) {
      dlStatusEl.hidden = true;
      dlStatusEl.textContent = "";
      return;
    }
    dlStatusEl.hidden = false;
    dlStatusEl.textContent = text;
    dlStatusEl.classList.toggle("revenue-status-error", !!isError);
  }

  function setDlWarn(text) {
    if (!dlWarnEl) return;
    if (!text) {
      dlWarnEl.hidden = true;
      dlWarnEl.textContent = "";
      return;
    }
    dlWarnEl.hidden = false;
    dlWarnEl.textContent = text;
  }

  function setExpStatus(text, isError) {
    if (!expStatus) return;
    if (!text) {
      expStatus.hidden = true;
      expStatus.textContent = "";
      return;
    }
    expStatus.hidden = false;
    expStatus.textContent = text;
    expStatus.classList.toggle("revenue-status-error", !!isError);
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function formatAmount(n) {
    const num = Number(n);
    if (!Number.isFinite(num)) return "—";
    return num.toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 4,
    });
  }

  function formatUnits(n) {
    const num = Number(n);
    if (!Number.isFinite(num)) return "—";
    return num.toLocaleString(undefined, {
      maximumFractionDigits: 2,
    });
  }

  function renderCurrencyMap(container, map, opts) {
    if (!container) return;
    const options = opts || {};
    container.innerHTML = "";
    const entries = Object.entries(map || {});
    if (!entries.length) {
      container.innerHTML = '<p class="revenue-kpi-placeholder">—</p>';
      return;
    }
    const frag = document.createDocumentFragment();
    for (const [cur, amt] of entries) {
      const line = document.createElement("p");
      line.className = "revenue-kpi-amount";
      if (options.signed) {
        const num = Number(amt);
        if (Number.isFinite(num) && num < 0) {
          line.classList.add("is-negative");
        } else if (Number.isFinite(num) && num > 0) {
          line.classList.add("is-positive");
        }
      }
      line.textContent = `${formatAmount(amt)} ${cur}`;
      frag.appendChild(line);
    }
    container.appendChild(frag);
  }

  function applySnapshot(snapshot) {
    if (!snapshot) return;
    renderCurrencyMap(kpiAlltimeAmounts, snapshot.all_time);
    renderCurrencyMap(kpiMonthAmounts, snapshot.current_month);
    renderCurrencyMap(kpiAlltimeExpenses, snapshot.expenses_all_time);
    renderCurrencyMap(kpiMonthExpenses, snapshot.expenses_current_month);
    renderCurrencyMap(kpiAlltimeProfit, snapshot.profit_all_time, { signed: true });
    renderCurrencyMap(kpiMonthProfit, snapshot.profit_current_month, {
      signed: true,
    });
    if (kpiAlltimeMeta) {
      const from = snapshot.tracked_from || "";
      const to = snapshot.tracked_to || "";
      const n = snapshot.expense_count || 0;
      if (from && to) {
        kpiAlltimeMeta.textContent = `Tracked ${from} → ${to} · ${n} expense(s) · profit = rev − exp`;
      } else {
        kpiAlltimeMeta.textContent = `${n} expense(s) · widen From + Refresh to grow revenue`;
      }
    }
    if (kpiMonthMeta) {
      const label = snapshot.current_month_label || "";
      kpiMonthMeta.textContent = label
        ? `${label} · profit = rev − exp (same currency)`
        : "Profit = rev − exp (same currency)";
    }
  }

  function applyFilters(filters) {
    if (!filters || typeof filters !== "object") return;
    if (filters.kind) kindEl.value = filters.kind;
    if (filters.from) fromEl.value = filters.from;
    if (filters.to) toEl.value = filters.to;
    if (Array.isArray(filters.sources)) setSourceChecks(filters.sources);
  }

  function applyDownloadFilters(filters) {
    if (!filters || typeof filters !== "object") return;
    if (dlFromEl && filters.from) dlFromEl.value = filters.from;
    if (dlToEl && filters.to) dlToEl.value = filters.to;
    if (Array.isArray(filters.sources)) setDownloadSourceChecks(filters.sources);
  }

  function renderUnitsMap(container, map) {
    if (!container) return;
    container.innerHTML = "";
    const entries = Object.entries(map || {});
    if (!entries.length) {
      container.innerHTML = '<p class="revenue-kpi-placeholder">—</p>';
      return;
    }
    const frag = document.createDocumentFragment();
    for (const [src, units] of entries) {
      const line = document.createElement("p");
      line.className = "revenue-kpi-amount";
      line.textContent = `${formatUnits(units)} ${src}`;
      frag.appendChild(line);
    }
    container.appendChild(frag);
  }

  function renderUnitsTotal(container, total) {
    if (!container) return;
    container.innerHTML = "";
    const line = document.createElement("p");
    line.className = "revenue-kpi-amount";
    if (total == null || !Number.isFinite(Number(total))) {
      container.innerHTML = '<p class="revenue-kpi-placeholder">—</p>';
      return;
    }
    line.textContent = formatUnits(total);
    container.appendChild(line);
  }

  function applyDownloadsSnapshot(snapshot) {
    if (!snapshot) return;
    renderUnitsTotal(dlKpiAlltimeTotal, snapshot.all_time_total);
    renderUnitsMap(dlKpiAlltimeBySource, snapshot.all_time);
    renderUnitsTotal(dlKpiMonthTotal, snapshot.current_month_total);
    renderUnitsMap(dlKpiMonthBySource, snapshot.current_month);
    if (dlKpiAlltimeMeta) {
      const from = snapshot.tracked_from || "";
      const to = snapshot.tracked_to || "";
      if (from && to) {
        dlKpiAlltimeMeta.textContent = `Tracked ${from} → ${to} · widen From + Refresh to grow`;
      } else {
        dlKpiAlltimeMeta.textContent = "Widen From + Refresh to grow tracked downloads";
      }
    }
    if (dlKpiMonthMeta) {
      const label = snapshot.current_month_label || "";
      dlKpiMonthMeta.textContent = label
        ? `${label} · from tracked download ledger`
        : "From tracked download ledger";
    }
  }

  function applyLastLoad(last) {
    if (!last || typeof last !== "object") return;
    const errors = last.errors || {};
    const errParts = Object.entries(errors).map(([src, msg]) => `${src}: ${msg}`);
    setWarn(errParts.join(" · ") || "");
    if (last.warnings && last.warnings.length) {
      setWarn(
        [warnEl.textContent, last.warnings.join(" · ")].filter(Boolean).join(" · ")
      );
    }
    const rowCount = (last.rows && last.rows.length) || 0;
    const when = last.loaded_at ? ` · saved ${last.loaded_at}` : "";
    setStatus(
      `Cached ${rowCount} row(s) · ${last.from || "?"} → ${last.to || "?"} · ${
        last.kind || "estimated"
      }${when}`
    );
    renderSummary(last.summary, last.kind || kindEl.value);
    renderRows(last.rows || []);
    loadedOnce = rowCount > 0 || !!last.loaded_at;
  }

  function applyLastDownloadsLoad(last) {
    if (!last || typeof last !== "object" || !dlSummaryEl || !dlTbody) return;
    const errors = last.errors || {};
    const errParts = Object.entries(errors).map(([src, msg]) => `${src}: ${msg}`);
    setDlWarn(errParts.join(" · ") || "");
    if (last.warnings && last.warnings.length) {
      setDlWarn(
        [dlWarnEl && dlWarnEl.textContent, last.warnings.join(" · ")]
          .filter(Boolean)
          .join(" · ")
      );
    }
    const rowCount = (last.rows && last.rows.length) || 0;
    const when = last.loaded_at ? ` · saved ${last.loaded_at}` : "";
    const total = (last.summary && last.summary.total_units) || 0;
    setDlStatus(
      `Cached ${rowCount} row(s) · ${formatUnits(total)} units · ${last.from || "?"} → ${
        last.to || "?"
      }${when}`
    );
    renderDownloadSummary(last.summary);
    renderDownloadRows(last.rows || []);
    downloadsLoadedOnce = rowCount > 0 || !!last.loaded_at;
  }

  function currentFilters() {
    return {
      kind: kindEl.value || "estimated",
      from: fromEl.value || "",
      to: toEl.value || "",
      sources: selectedSources(),
    };
  }

  function currentDownloadFilters() {
    return {
      from: (dlFromEl && dlFromEl.value) || "",
      to: (dlToEl && dlToEl.value) || "",
      sources: selectedDownloadSources(),
    };
  }

  function persistUiSoon() {
    if (persistTimer) clearTimeout(persistTimer);
    persistTimer = setTimeout(() => {
      persistUi();
    }, 400);
  }

  async function persistUi() {
    try {
      await fetch("/api/revenue/tab", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          active_subtab: activeSub,
          filters: currentFilters(),
          download_filters: currentDownloadFilters(),
        }),
      });
    } catch (_) {
      /* ignore */
    }
  }

  async function loadTabState() {
    try {
      const res = await fetch("/api/revenue/snapshot");
      const payload = await res.json();
      if (!payload || payload.ok === false) return false;
      applySnapshot(payload.snapshot);
      applyFilters(payload.filters);
      applyDownloadFilters(payload.download_filters);
      if (payload.downloads_snapshot) {
        applyDownloadsSnapshot(payload.downloads_snapshot);
      }
      if (payload.last_load) {
        applyLastLoad(payload.last_load);
      }
      if (payload.last_downloads_load) {
        applyLastDownloadsLoad(payload.last_downloads_load);
      }
      if (Array.isArray(payload.expenses)) {
        renderExpenses(payload.expenses);
        expensesLoaded = true;
      }
      if (payload.active_subtab) {
        setSubtab(payload.active_subtab, { persist: false });
      }
      return !!payload.last_load;
    } catch (_) {
      return false;
    }
  }

  function setSubtab(name, opts) {
    const persist = !opts || opts.persist !== false;
    if (name === "expense") activeSub = "expense";
    else if (name === "downloads") activeSub = "downloads";
    else activeSub = "revenue";
    if (subtabs) {
      subtabs.querySelectorAll(".revenue-subtab").forEach((btn) => {
        const on = btn.getAttribute("data-rev-tab") === activeSub;
        btn.classList.toggle("active", on);
      });
    }
    if (panelRevenue) panelRevenue.hidden = activeSub !== "revenue";
    if (panelDownloads) panelDownloads.hidden = activeSub !== "downloads";
    if (panelExpense) panelExpense.hidden = activeSub !== "expense";
    if (activeSub === "expense" && !expensesLoaded) {
      loadExpenses();
    }
    if (activeSub === "downloads" && !downloadsLoadedOnce) {
      loadDownloads();
    }
    if (persist) persistUiSoon();
  }

  function renderSummary(summary, kind) {
    summaryEl.innerHTML = "";
    if (!summary) {
      summaryEl.innerHTML =
        '<p class="revenue-empty">No summary yet.</p>';
      return;
    }
    const bySource = summary.by_source || {};
    const sources = Object.keys(bySource);
    if (!sources.length) {
      summaryEl.innerHTML =
        '<p class="revenue-empty">No rows in range (check credentials / dates).</p>';
      return;
    }
    const frag = document.createDocumentFragment();
    const note = document.createElement("p");
    note.className = "revenue-hint";
    note.textContent = summary.mixed_currency
      ? `${kind}: totals by source — mixed currencies (not summed across FX).`
      : `${kind}: totals by source.`;
    frag.appendChild(note);

    const grid = document.createElement("div");
    grid.className = "revenue-summary-grid";
    for (const src of sources) {
      const curMap = bySource[src] || {};
      const card = document.createElement("div");
      card.className = "revenue-card";
      const title = document.createElement("h3");
      title.textContent = src;
      card.appendChild(title);
      for (const [cur, amt] of Object.entries(curMap)) {
        const line = document.createElement("p");
        line.className = "revenue-card-amount";
        line.textContent = `${formatAmount(amt)} ${cur}`;
        card.appendChild(line);
      }
      grid.appendChild(card);
    }
    frag.appendChild(grid);
    summaryEl.appendChild(frag);
  }

  function renderDownloadSummary(summary) {
    if (!dlSummaryEl) return;
    dlSummaryEl.innerHTML = "";
    if (!summary) {
      dlSummaryEl.innerHTML = '<p class="revenue-empty">No summary yet.</p>';
      return;
    }
    const bySource = summary.by_source || {};
    const sources = Object.keys(bySource);
    const frag = document.createDocumentFragment();
    const note = document.createElement("p");
    note.className = "revenue-hint";
    note.textContent = `Total units in range: ${formatUnits(summary.total_units || 0)}`;
    frag.appendChild(note);
    if (!sources.length) {
      const empty = document.createElement("p");
      empty.className = "revenue-empty";
      empty.textContent = "No download rows in range.";
      frag.appendChild(empty);
      dlSummaryEl.appendChild(frag);
      return;
    }
    const grid = document.createElement("div");
    grid.className = "revenue-summary-grid";
    for (const src of sources) {
      const card = document.createElement("div");
      card.className = "revenue-card";
      const title = document.createElement("h3");
      title.textContent = src;
      card.appendChild(title);
      const line = document.createElement("p");
      line.className = "revenue-card-amount";
      line.textContent = `${formatUnits(bySource[src])} units`;
      card.appendChild(line);
      grid.appendChild(card);
    }
    frag.appendChild(grid);
    dlSummaryEl.appendChild(frag);
  }

  function renderRows(rows) {
    tbody.innerHTML = "";
    if (!rows || !rows.length) {
      tbody.innerHTML =
        '<tr><td colspan="7" class="revenue-empty-cell">No rows returned.</td></tr>';
      return;
    }
    const frag = document.createDocumentFragment();
    for (const row of rows) {
      const tr = document.createElement("tr");
      tr.innerHTML = [
        escapeHtml(row.date || ""),
        escapeHtml(row.source || ""),
        escapeHtml(row.label || row.app_id || ""),
        escapeHtml(formatAmount(row.amount)),
        escapeHtml(row.currency || ""),
        row.units == null ? "—" : escapeHtml(String(row.units)),
        escapeHtml(row.kind || ""),
      ]
        .map((cell) => `<td>${cell}</td>`)
        .join("");
      frag.appendChild(tr);
    }
    tbody.appendChild(frag);
  }

  function renderDownloadRows(rows) {
    if (!dlTbody) return;
    dlTbody.innerHTML = "";
    if (!rows || !rows.length) {
      dlTbody.innerHTML =
        '<tr><td colspan="4" class="revenue-empty-cell">No rows returned.</td></tr>';
      return;
    }
    const frag = document.createDocumentFragment();
    for (const row of rows) {
      const tr = document.createElement("tr");
      tr.innerHTML = [
        escapeHtml(row.date || ""),
        escapeHtml(row.source || ""),
        escapeHtml(row.label || row.app_id || ""),
        escapeHtml(formatUnits(row.units)),
      ]
        .map((cell) => `<td>${cell}</td>`)
        .join("");
      frag.appendChild(tr);
    }
    dlTbody.appendChild(frag);
  }

  function renderExpenses(expenses) {
    if (!expTbody) return;
    expTbody.innerHTML = "";
    if (!expenses || !expenses.length) {
      expTbody.innerHTML =
        '<tr><td colspan="6" class="revenue-empty-cell">No expenses yet.</td></tr>';
      return;
    }
    const frag = document.createDocumentFragment();
    for (const row of expenses) {
      const tr = document.createElement("tr");
      const id = escapeHtml(row.id || "");
      tr.innerHTML = [
        escapeHtml(row.date || ""),
        escapeHtml(row.type || ""),
        escapeHtml(formatAmount(row.amount)),
        escapeHtml(row.currency || ""),
        escapeHtml(row.description || ""),
        `<button type="button" class="expense-delete" data-id="${id}" aria-label="Delete expense">Delete</button>`,
      ]
        .map((cell) => `<td>${cell}</td>`)
        .join("");
      frag.appendChild(tr);
    }
    expTbody.appendChild(frag);
  }

  async function loadExpenses() {
    if (!expTbody) return;
    setExpStatus("Loading expenses…");
    try {
      const res = await fetch("/api/expenses");
      const payload = await res.json();
      if (!payload || payload.ok === false) {
        const msg =
          (payload && payload.error && payload.error.message) ||
          `Request failed (${res.status})`;
        setExpStatus(msg, true);
        return;
      }
      renderExpenses(payload.expenses || []);
      expensesLoaded = true;
      setExpStatus("");
    } catch (err) {
      setExpStatus(err.message || "Failed to load expenses", true);
    }
  }

  async function load() {
    if (loading) return;
    const sources = selectedSources();
    if (!sources.length) {
      setStatus("Select at least one source.", true);
      return;
    }
    loading = true;
    refreshBtn.disabled = true;
    setStatus("Loading…");
    setWarn("");
    try {
      const params = new URLSearchParams({
        sources: sources.join(","),
        kind: kindEl.value || "estimated",
        from: fromEl.value || "",
        to: toEl.value || "",
      });
      const res = await fetch(`/api/revenue/series?${params.toString()}`);
      const payload = await res.json();
      if (!payload || payload.ok === false) {
        const msg =
          (payload && payload.error && payload.error.message) ||
          `Request failed (${res.status})`;
        setStatus(msg, true);
        renderSummary(null, kindEl.value);
        renderRows([]);
        return;
      }
      const errors = payload.errors || {};
      const errParts = Object.entries(errors).map(
        ([src, msg]) => `${src}: ${msg}`
      );
      if (errParts.length) {
        setWarn(errParts.join(" · "));
      }
      if (payload.warnings && payload.warnings.length) {
        setWarn(
          [warnEl.textContent, payload.warnings.join(" · ")]
            .filter(Boolean)
            .join(" · ")
        );
      }
      if (payload.snapshot) {
        applySnapshot(payload.snapshot);
      }
      const rowCount = (payload.rows && payload.rows.length) || 0;
      setStatus(
        `Loaded ${rowCount} row(s) · ${payload.from} → ${payload.to} · ${payload.kind} · saved`
      );
      renderSummary(payload.summary, payload.kind);
      renderRows(payload.rows || []);
      loadedOnce = true;
      await persistUi();
    } catch (err) {
      setStatus(err.message || "Failed to load revenue", true);
    } finally {
      loading = false;
      refreshBtn.disabled = false;
    }
  }

  async function loadDownloads() {
    if (dlLoading || !dlRefreshBtn) return;
    const sources = selectedDownloadSources();
    if (!sources.length) {
      setDlStatus("Select at least one source.", true);
      return;
    }
    dlLoading = true;
    dlRefreshBtn.disabled = true;
    setDlStatus("Loading…");
    setDlWarn("");
    try {
      const params = new URLSearchParams({
        sources: sources.join(","),
        from: (dlFromEl && dlFromEl.value) || "",
        to: (dlToEl && dlToEl.value) || "",
      });
      const res = await fetch(`/api/downloads/series?${params.toString()}`);
      const payload = await res.json();
      if (!payload || payload.ok === false) {
        const msg =
          (payload && payload.error && payload.error.message) ||
          `Request failed (${res.status})`;
        setDlStatus(msg, true);
        renderDownloadSummary(null);
        renderDownloadRows([]);
        return;
      }
      const errors = payload.errors || {};
      const errParts = Object.entries(errors).map(
        ([src, msg]) => `${src}: ${msg}`
      );
      if (errParts.length) {
        setDlWarn(errParts.join(" · "));
      }
      if (payload.warnings && payload.warnings.length) {
        setDlWarn(
          [dlWarnEl && dlWarnEl.textContent, payload.warnings.join(" · ")]
            .filter(Boolean)
            .join(" · ")
        );
      }
      const rowCount = (payload.rows && payload.rows.length) || 0;
      const total = (payload.summary && payload.summary.total_units) || 0;
      setDlStatus(
        `Loaded ${rowCount} row(s) · ${formatUnits(total)} units · ${payload.from} → ${
          payload.to
        } · saved`
      );
      renderDownloadSummary(payload.summary);
      renderDownloadRows(payload.rows || []);
      if (payload.downloads_snapshot) {
        applyDownloadsSnapshot(payload.downloads_snapshot);
      }
      downloadsLoadedOnce = true;
      await persistUi();
    } catch (err) {
      setDlStatus(err.message || "Failed to load downloads", true);
    } finally {
      dlLoading = false;
      dlRefreshBtn.disabled = false;
    }
  }

  refreshBtn.addEventListener("click", () => {
    load();
  });
  if (dlRefreshBtn) {
    dlRefreshBtn.addEventListener("click", () => {
      loadDownloads();
    });
  }

  [kindEl, fromEl, toEl].forEach((el) => {
    el.addEventListener("change", persistUiSoon);
  });
  document.querySelectorAll('input[name="rev-source"]').forEach((el) => {
    el.addEventListener("change", persistUiSoon);
  });
  [dlFromEl, dlToEl].forEach((el) => {
    if (el) el.addEventListener("change", persistUiSoon);
  });
  document.querySelectorAll('input[name="dl-source"]').forEach((el) => {
    el.addEventListener("change", persistUiSoon);
  });

  if (subtabs) {
    subtabs.addEventListener("click", (event) => {
      const btn = event.target.closest(".revenue-subtab");
      if (!btn || !subtabs.contains(btn)) return;
      setSubtab(btn.getAttribute("data-rev-tab") || "revenue");
    });
  }

  if (expenseForm) {
    expenseForm.addEventListener("submit", async (event) => {
      event.preventDefault();
      const amount = Number(expAmount && expAmount.value);
      if (!Number.isFinite(amount)) {
        setExpStatus("Enter a valid amount.", true);
        return;
      }
      setExpStatus("Saving…");
      try {
        const res = await fetch("/api/expenses", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            type: (expType && expType.value) || "other",
            amount,
            currency: (expCurrency && expCurrency.value) || "USD",
            description: (expDescription && expDescription.value) || "",
          }),
        });
        const payload = await res.json();
        if (!payload || payload.ok === false) {
          const msg =
            (payload && payload.error && payload.error.message) ||
            `Save failed (${res.status})`;
          setExpStatus(msg, true);
          return;
        }
        if (expDescription) expDescription.value = "";
        if (expAmount) expAmount.value = "";
        setExpStatus("Saved · persisted in revenue_ledger.json");
        if (payload.snapshot) applySnapshot(payload.snapshot);
        await loadExpenses();
      } catch (err) {
        setExpStatus(err.message || "Failed to save expense", true);
      }
    });
  }

  if (expTbody) {
    expTbody.addEventListener("click", async (event) => {
      const btn = event.target.closest(".expense-delete");
      if (!btn || !expTbody.contains(btn)) return;
      const id = btn.getAttribute("data-id");
      if (!id) return;
      setExpStatus("Deleting…");
      try {
        const res = await fetch(`/api/expenses/${encodeURIComponent(id)}`, {
          method: "DELETE",
        });
        const payload = await res.json();
        if (!payload || payload.ok === false) {
          const msg =
            (payload && payload.error && payload.error.message) ||
            `Delete failed (${res.status})`;
          setExpStatus(msg, true);
          return;
        }
        setExpStatus("Deleted.");
        if (payload.snapshot) applySnapshot(payload.snapshot);
        await loadExpenses();
      } catch (err) {
        setExpStatus(err.message || "Failed to delete", true);
      }
    });
  }

  window.RevenueDash = {
    async onView(view) {
      if (view !== "revenue") return;
      const hadCache = await loadTabState();
      // Only auto-fetch revenue when nothing is saved yet
      if (!hadCache && !loadedOnce && activeSub === "revenue") {
        load();
      }
    },
  };
})();
