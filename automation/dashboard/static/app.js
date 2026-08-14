(() => {
  const sessionMetaEl = document.getElementById("session-meta");
  const accordionNavEl = document.getElementById("accordion-nav");
  const accordionContentEl = document.getElementById("accordion-content");
  const activeScriptEl = document.getElementById("active-script");
  const stopBtn = document.getElementById("stop-btn");
  const runBtn = document.getElementById("run-btn");
  const terminalToolbarEl = document.getElementById("terminal-toolbar");
  const sessionIdBtn = document.getElementById("session-id-btn");
  const copySessionIdBtn = document.getElementById("copy-session-id-btn");
  const terminalTabsEl = document.getElementById("terminal-tabs");
  const terminalStackEl = document.getElementById("terminal-stack");
  const terminalPlaceholderEl = document.getElementById("terminal-placeholder");
  const mainTabsEl = document.getElementById("main-tabs");
  const taskManagerFrame = document.getElementById("task-manager-frame");
  const taskManagerMissingEl = document.getElementById("task-manager-missing");
  const taskManagerStatusEl = document.getElementById("task-manager-status");

  /** @type {Map<string, {
   *   scriptId: string,
   *   logFile: string | null,
   *   runnable: boolean,
   *   term: Terminal,
   *   fitAddon: FitAddon,
   *   hostEl: HTMLElement,
   *   tabEl: HTMLButtonElement | null,
   *   ws: WebSocket | null,
   *   running: boolean,
   *   onDataDisposable: { dispose: () => void } | null,
   * }>} */
  const sessions = new Map();

  let activeScriptId = null;
  let activeGroup = null;
  let groupedScripts = [];
  let activeView = "scripts";
  let taskManagerUrl = "";

  function isAbsoluteHttpUrl(value) {
    return /^https?:\/\/[^/\s]+/i.test(value);
  }

  function setTaskManagerStatus(text) {
    if (!taskManagerStatusEl) {
      return;
    }
    if (!text) {
      taskManagerStatusEl.hidden = true;
      taskManagerStatusEl.textContent = "";
      return;
    }
    taskManagerStatusEl.hidden = false;
    taskManagerStatusEl.textContent = text;
  }

  function ensureEmbedLoaded(frame) {
    if (!frame) {
      return;
    }
    if (!taskManagerUrl || !isAbsoluteHttpUrl(taskManagerUrl)) {
      frame.removeAttribute("src");
      frame.hidden = true;
      if (taskManagerMissingEl) {
        taskManagerMissingEl.hidden = false;
      }
      setTaskManagerStatus("");
      frame.dataset.loaded = "";
      return;
    }
    if (frame.dataset.loaded === "1" && frame.getAttribute("src") === taskManagerUrl) {
      frame.hidden = false;
      if (taskManagerMissingEl) {
        taskManagerMissingEl.hidden = true;
      }
      setTaskManagerStatus(taskManagerUrl);
      return;
    }
    frame.hidden = false;
    if (taskManagerMissingEl) {
      taskManagerMissingEl.hidden = true;
    }
    // Never assign relative/empty src — browsers resolve "" to this dashboard origin.
    frame.src = taskManagerUrl;
    frame.dataset.loaded = "1";
    setTaskManagerStatus(taskManagerUrl);
  }

  function setActiveView(view) {
    activeView = view;

    mainTabsEl.querySelectorAll(".main-tab").forEach((tab) => {
      const isActive = tab.dataset.view === view;
      tab.classList.toggle("active", isActive);
      tab.setAttribute("aria-selected", isActive ? "true" : "false");
    });

    document.querySelectorAll(".view-panel").forEach((panel) => {
      const isActive = panel.dataset.view === view;
      panel.classList.toggle("active", isActive);
      panel.hidden = !isActive;
    });

    if (view === "task-manager") {
      ensureEmbedLoaded(taskManagerFrame);
    }

    if (window.DocsDash && typeof window.DocsDash.onView === "function") {
      window.DocsDash.onView(view);
    }

    if (view === "scripts" && activeScriptId) {
      const session = sessions.get(activeScriptId);
      if (session) {
        requestAnimationFrame(() => {
          session.fitAddon.fit();
          if (session.ws && session.ws.readyState === WebSocket.OPEN) {
            session.ws.send(
              JSON.stringify({
                type: "resize",
                cols: session.term.cols,
                rows: session.term.rows,
              })
            );
          }
        });
      }
    }
  }

  function basename(scriptId) {
    return scriptId.split("/").pop();
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function updateToolbar() {
    const session = activeScriptId ? sessions.get(activeScriptId) : null;
    const hasSession = Boolean(session);
    terminalToolbarEl.hidden = !hasSession;
    stopBtn.disabled = !(session && session.running);
    runBtn.disabled = !(session && session.runnable);
    copySessionIdBtn.disabled = !(session && session.logFile);
    if (session) {
      const logLabel = session.logFile || "(no log yet — run script)";
      sessionIdBtn.textContent = logLabel;
      sessionIdBtn.title = session.logFile || "Run the script to create a log file";
      sessionIdBtn.disabled = !session.logFile;
      activeScriptEl.textContent = session.scriptId;
    } else {
      sessionIdBtn.textContent = "";
      sessionIdBtn.title = "";
      sessionIdBtn.disabled = true;
      activeScriptEl.textContent = "";
    }
  }

  function renderSession(session) {
    const brand = String(session.repo_brand || "").trim() || "dashboard";
    const brandTitle = `${brand} dashboard`;
    const brandEl = document.getElementById("dashboard-brand-title");
    if (brandEl) {
      brandEl.textContent = brandTitle;
    }
    document.title = brandTitle;

    if (!session.env_file) {
      sessionMetaEl.textContent = `${session.mode} · ${session.profile}`;
      return;
    }
    const envName = session.env_file_name || session.env_file.split("/").pop();
    sessionMetaEl.replaceChildren();

    const modeRow = document.createElement("div");
    modeRow.innerHTML = `<strong>mode</strong> ${escapeHtml(session.mode)}`;
    sessionMetaEl.appendChild(modeRow);

    const envRow = document.createElement("div");
    const envLabel = document.createElement("strong");
    envLabel.textContent = "env ";
    const envLink = document.createElement("a");
    envLink.className = "env-file-link";
    envLink.href = "#";
    envLink.textContent = envName;
    envLink.title = session.env_file;
    envLink.addEventListener("click", async (event) => {
      event.preventDefault();
      const res = await fetch("/api/open-env-file", { method: "POST" });
      if (!res.ok) {
        const active = activeScriptId ? sessions.get(activeScriptId) : null;
        if (active) {
          active.term.writeln("\r\n\x1b[31mCould not open env file\x1b[0m");
        }
      }
    });
    envRow.appendChild(envLabel);
    envRow.appendChild(envLink);
    sessionMetaEl.appendChild(envRow);
  }

  function groupScripts(scripts) {
    const groups = new Map();
    for (const script of scripts) {
      const key = script.group || "other";
      if (!groups.has(key)) {
        groups.set(key, []);
      }
      groups.get(key).push(script);
    }
    return [...groups.entries()].sort(([a], [b]) => a.localeCompare(b));
  }

  function markSidebarActive(scriptId) {
    document.querySelectorAll(".script-link").forEach((el) => {
      el.classList.toggle("active", el.dataset.scriptId === scriptId);
      el.classList.toggle("has-terminal", sessions.has(el.dataset.scriptId));
      el.classList.toggle(
        "running",
        sessions.get(el.dataset.scriptId)?.running === true
      );
    });
  }

  function renderTerminalTabs() {
    terminalTabsEl.replaceChildren();
    for (const [scriptId, session] of sessions) {
      const tab = document.createElement("button");
      tab.type = "button";
      tab.className = "terminal-tab";
      if (scriptId === activeScriptId) {
        tab.classList.add("active");
      }
      if (session.running) {
        tab.classList.add("running");
      }
      tab.dataset.scriptId = scriptId;
      tab.title = session.logFile
        ? `${scriptId}\n${session.logFile}`
        : scriptId;
      tab.innerHTML = `
        <span class="terminal-tab-label">${escapeHtml(basename(scriptId))}</span>
        <span class="terminal-tab-close" title="Close terminal" aria-label="Close">×</span>
      `;
      tab.addEventListener("click", (event) => {
        const close = event.target.closest(".terminal-tab-close");
        if (close) {
          event.stopPropagation();
          closeTerminalSession(scriptId);
          return;
        }
        focusTerminal(scriptId);
      });
      session.tabEl = tab;
      terminalTabsEl.appendChild(tab);
    }
  }

  function focusTerminal(scriptId) {
    if (!sessions.has(scriptId)) {
      return;
    }
    activeScriptId = scriptId;
    terminalPlaceholderEl.hidden = true;

    for (const [id, session] of sessions) {
      session.hostEl.hidden = id !== scriptId;
      if (session.tabEl) {
        session.tabEl.classList.toggle("active", id === scriptId);
      }
    }

    const session = sessions.get(scriptId);
    requestAnimationFrame(() => {
      session.fitAddon.fit();
      session.term.focus();
      if (session.ws && session.ws.readyState === WebSocket.OPEN) {
        session.ws.send(
          JSON.stringify({
            type: "resize",
            cols: session.term.cols,
            rows: session.term.rows,
          })
        );
      }
    });

    markSidebarActive(scriptId);
    updateToolbar();
  }

  function openTerminalPanel(scriptId, { runnable = true } = {}) {
    let session = sessions.get(scriptId);
    if (!session) {
      const hostEl = document.createElement("div");
      hostEl.className = "terminal-host";
      hostEl.dataset.scriptId = scriptId;
      hostEl.hidden = true;
      terminalStackEl.appendChild(hostEl);
      terminalPlaceholderEl.hidden = true;

      const term = new Terminal({
        cursorBlink: true,
        fontFamily:
          "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
        fontSize: 13,
        theme: {
          background: "#0f1117",
          foreground: "#e6eaf2",
        },
      });
      const fitAddon = new FitAddon.FitAddon();
      term.loadAddon(fitAddon);
      term.open(hostEl);

      session = {
        scriptId,
        logFile: null,
        runnable,
        term,
        fitAddon,
        hostEl,
        tabEl: null,
        ws: null,
        running: false,
        onDataDisposable: null,
      };
      sessions.set(scriptId, session);
      renderTerminalTabs();
      term.writeln(`\x1b[90mTerminal ready — press Run script to start\x1b[0m`);
    }
    focusTerminal(scriptId);
    return session;
  }

  function stopSession(scriptId, { writeStopped = false } = {}) {
    const session = sessions.get(scriptId);
    if (!session) {
      return;
    }
    if (session.ws) {
      session.ws.close();
      session.ws = null;
    }
    if (session.onDataDisposable) {
      session.onDataDisposable.dispose();
      session.onDataDisposable = null;
    }
    session.running = false;
    if (writeStopped) {
      session.term.writeln("\r\n\x1b[33m[stopped by user]\x1b[0m");
    }
    if (session.tabEl) {
      session.tabEl.classList.remove("running");
    }
    markSidebarActive(activeScriptId);
    updateToolbar();
    renderTerminalTabs();
  }

  function closeTerminalSession(scriptId) {
    const session = sessions.get(scriptId);
    if (!session) {
      return;
    }
    stopSession(scriptId);
    session.term.dispose();
    session.hostEl.remove();
    sessions.delete(scriptId);
    renderTerminalTabs();

    if (activeScriptId === scriptId) {
      const remaining = [...sessions.keys()];
      if (remaining.length > 0) {
        focusTerminal(remaining[remaining.length - 1]);
      } else {
        activeScriptId = null;
        terminalPlaceholderEl.hidden = false;
        markSidebarActive(null);
        updateToolbar();
      }
    } else {
      markSidebarActive(activeScriptId);
      updateToolbar();
    }
  }

  function wsUrl(scriptId, cols, rows) {
    const params = new URLSearchParams({
      script: scriptId,
      cols: String(cols),
      rows: String(rows),
    });
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    return `${proto}//${window.location.host}/ws/run?${params.toString()}`;
  }

  function runActiveScript() {
    if (!activeScriptId) {
      return;
    }
    const session = sessions.get(activeScriptId);
    if (!session || !session.runnable) {
      return;
    }

    stopSession(activeScriptId);
    session.term.reset();
    session.logFile = null;
    session.running = true;
    updateToolbar();
    renderTerminalTabs();
    markSidebarActive(activeScriptId);

    session.fitAddon.fit();
    const ws = new WebSocket(
      wsUrl(activeScriptId, session.term.cols || 80, session.term.rows || 24)
    );
    ws.binaryType = "arraybuffer";
    session.ws = ws;

    ws.addEventListener("open", () => {
      session.term.focus();
    });

    ws.addEventListener("message", (event) => {
      if (typeof event.data === "string") {
        try {
          const payload = JSON.parse(event.data);
          if (payload.type === "error") {
            session.term.writeln(`\r\n\x1b[31m${payload.message}\x1b[0m`);
            session.running = false;
            updateToolbar();
            renderTerminalTabs();
            markSidebarActive(activeScriptId);
          } else if (payload.type === "started") {
            session.term.writeln(`\r\n\x1b[36m▶ ${payload.script}\x1b[0m`);
            if (payload.log_file) {
              session.logFile = payload.log_file;
              session.term.writeln(`\x1b[90mlog: ${payload.log_file}\x1b[0m\r\n`);
            } else {
              session.logFile = null;
              session.term.writeln("");
            }
            updateToolbar();
          } else if (payload.type === "exit") {
            session.term.writeln(`\r\n\x1b[33m[exit ${payload.code}]\x1b[0m`);
            if (payload.log_file) {
              session.logFile = payload.log_file;
              session.term.writeln(`\x1b[90mlog: ${payload.log_file}\x1b[0m`);
            }
            session.running = false;
            updateToolbar();
            renderTerminalTabs();
            markSidebarActive(activeScriptId);
          }
        } catch (_err) {
          session.term.write(event.data);
        }
        return;
      }

      session.term.write(new Uint8Array(event.data));
    });

    ws.addEventListener("close", () => {
      if (session.ws === ws) {
        session.ws = null;
        session.running = false;
        updateToolbar();
        renderTerminalTabs();
        markSidebarActive(activeScriptId);
      }
    });

    ws.addEventListener("error", () => {
      session.term.writeln("\r\n\x1b[31mWebSocket connection failed\x1b[0m");
      session.running = false;
      updateToolbar();
      renderTerminalTabs();
      markSidebarActive(activeScriptId);
    });

    session.onDataDisposable = session.term.onData((data) => {
      if (session.ws && session.ws.readyState === WebSocket.OPEN) {
        session.ws.send(JSON.stringify({ type: "input", data }));
      }
    });
  }

  async function copyLogPath() {
    const session = activeScriptId ? sessions.get(activeScriptId) : null;
    if (!session) {
      return;
    }
    if (!session.logFile) {
      session.term.writeln(
        "\r\n\x1b[33mNo log path yet — run the script first\x1b[0m",
      );
      return;
    }
    try {
      await navigator.clipboard.writeText(session.logFile);
      const previous = copySessionIdBtn.textContent;
      copySessionIdBtn.textContent = "Copied";
      setTimeout(() => {
        copySessionIdBtn.textContent = previous;
      }, 1000);
    } catch (_err) {
      session.term.writeln("\r\n\x1b[31mCould not copy log path\x1b[0m");
    }
  }

  function createScriptButton(script) {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "script-link";
    if (!script.runnable) {
      btn.classList.add("unsupported");
    }
    if (script.id === activeScriptId) {
      btn.classList.add("active");
    }
    if (sessions.has(script.id)) {
      btn.classList.add("has-terminal");
    }
    if (sessions.get(script.id)?.running) {
      btn.classList.add("running");
    }

    btn.dataset.scriptId = script.id;
    const descHtml = script.description
      ? `<span class="desc">${escapeHtml(script.description)}</span>`
      : "";
    btn.innerHTML = `
      <span class="name">${escapeHtml(basename(script.id))}</span>
      ${descHtml}
      <span class="meta">${escapeHtml(script.id)} · ${escapeHtml(script.profile)} · ${escapeHtml(script.kind)}</span>
    `;

    btn.addEventListener("click", () => {
      openTerminalPanel(script.id, { runnable: Boolean(script.runnable) });
      if (!script.runnable) {
        const session = sessions.get(script.id);
        session.term.writeln(`\r\nUnsupported script type: ${script.id}`);
      }
    });

    li.appendChild(btn);
    return li;
  }

  function renderGroupPanel(group, items) {
    const panel = document.createElement("div");
    panel.className = "accordion-panel";
    panel.dataset.group = group;
    panel.hidden = true;

    const list = document.createElement("ul");
    list.className = "script-list";
    for (const script of items) {
      list.appendChild(createScriptButton(script));
    }

    panel.appendChild(list);
    return panel;
  }

  function setActiveGroup(group) {
    activeGroup = group;

    accordionNavEl.querySelectorAll(".accordion-tab").forEach((tab) => {
      const isActive = tab.dataset.group === group;
      tab.classList.toggle("active", isActive);
      tab.setAttribute("aria-expanded", isActive ? "true" : "false");
    });

    accordionContentEl.querySelectorAll(".accordion-panel").forEach((panel) => {
      panel.hidden = panel.dataset.group !== group;
    });

    const placeholder = accordionContentEl.querySelector(".accordion-placeholder");
    if (placeholder) {
      placeholder.hidden = Boolean(group);
    }
  }

  function renderScripts(scripts) {
    groupedScripts = groupScripts(scripts);
    accordionNavEl.innerHTML = "";
    accordionContentEl.innerHTML =
      '<p class="accordion-placeholder">Select a section</p>';

    for (const [group, items] of groupedScripts) {
      const tab = document.createElement("button");
      tab.type = "button";
      tab.className = "accordion-tab";
      tab.dataset.group = group;
      tab.setAttribute("aria-expanded", "false");
      tab.innerHTML = `
        <span class="accordion-label">${escapeHtml(group)}</span>
        <span class="accordion-count">${items.length}</span>
      `;

      tab.addEventListener("click", () => {
        if (activeGroup === group) {
          setActiveGroup(null);
          return;
        }
        setActiveGroup(group);
      });

      accordionNavEl.appendChild(tab);
      accordionContentEl.appendChild(renderGroupPanel(group, items));
    }

    if (activeGroup && groupedScripts.some(([group]) => group === activeGroup)) {
      setActiveGroup(activeGroup);
    }
  }

  async function loadScripts() {
    const res = await fetch("/api/scripts");
    const scripts = await res.json();
    renderScripts(scripts);
  }

  async function loadSession() {
    const res = await fetch("/api/session");
    const session = await res.json();
    const nextUrl = session.task_manager_url || "";
    taskManagerUrl = isAbsoluteHttpUrl(nextUrl) ? nextUrl : "";
    renderSession(session);
    if (activeView === "task-manager") {
      ensureEmbedLoaded(taskManagerFrame);
    }
  }

  runBtn.addEventListener("click", () => {
    runActiveScript();
  });

  mainTabsEl.addEventListener("click", (event) => {
    const tab = event.target.closest(".main-tab");
    if (!tab || !mainTabsEl.contains(tab)) {
      return;
    }
    const view = tab.dataset.view;
    if (view && view !== activeView) {
      setActiveView(view);
    }
  });

  sessionIdBtn.addEventListener("click", () => {
    copyLogPath();
  });

  copySessionIdBtn.addEventListener("click", () => {
    copyLogPath();
  });

  stopBtn.addEventListener("click", () => {
    if (!activeScriptId) {
      return;
    }
    stopSession(activeScriptId, { writeStopped: true });
  });

  window.addEventListener("resize", () => {
    for (const session of sessions.values()) {
      if (session.hostEl.hidden) {
        continue;
      }
      session.fitAddon.fit();
      if (session.ws && session.ws.readyState === WebSocket.OPEN) {
        session.ws.send(
          JSON.stringify({
            type: "resize",
            cols: session.term.cols,
            rows: session.term.rows,
          })
        );
      }
    }
  });

  Promise.all([loadSession(), loadScripts()]).catch((err) => {
    terminalPlaceholderEl.textContent = `Failed to load dashboard: ${err}`;
  });
})();
