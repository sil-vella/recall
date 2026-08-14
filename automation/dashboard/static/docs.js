(() => {
  "use strict";

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function githubSlug(text) {
    const s = String(text || "")
      .trim()
      .toLowerCase();
    let out = "";
    for (const ch of s) {
      if (/[a-z0-9 \-_]/.test(ch)) {
        out += ch;
      }
      // em/en dash dropped so surrounding spaces become --
    }
    return out.replace(/ /g, "-").replace(/^-+|-+$/g, "");
  }

  function configureMarked() {
    if (typeof marked === "undefined") {
      return;
    }
    const renderer = new marked.Renderer();
    renderer.heading = function heading(text, level, raw) {
      // marked v5+: (token); older: (text, level, raw)
      if (typeof text === "object" && text !== null) {
        const token = text;
        const depth = token.depth;
        const inner = token.text;
        const id = githubSlug(
          String(inner || "").replace(/<[^>]+>/g, "")
        );
        return `<h${depth} id="${escapeHtml(id)}">${inner}</h${depth}>\n`;
      }
      const id = githubSlug(raw || text);
      return `<h${level} id="${escapeHtml(id)}">${text}</h${level}>\n`;
    };
    marked.setOptions({
      gfm: true,
      breaks: false,
      renderer,
    });
  }

  function renderMarkdown(markdown) {
    if (typeof marked === "undefined") {
      return `<pre>${escapeHtml(markdown)}</pre>`;
    }
    return marked.parse(markdown || "");
  }

  function groupBy(items, keyFn) {
    const map = new Map();
    for (const item of items) {
      const key = keyFn(item);
      if (!map.has(key)) {
        map.set(key, []);
      }
      map.get(key).push(item);
    }
    return [...map.entries()];
  }

  function createDocsViewer(opts) {
    const {
      listUrl,
      navEl,
      contentEl,
      markdownEl,
      toolbarEl,
      titleEl,
      pathEl,
      mode,
    } = opts;

    let activeGroup = null;
    let activeDocPath = null;
    let activeSectionId = null;
    let cache = new Map();
    let loaded = false;

    function setActiveGroup(group) {
      activeGroup = group;
      navEl.querySelectorAll(".accordion-tab").forEach((tab) => {
        const isActive = tab.dataset.group === group;
        tab.classList.toggle("active", isActive);
        tab.setAttribute("aria-expanded", isActive ? "true" : "false");
      });
      contentEl.querySelectorAll(".accordion-panel").forEach((panel) => {
        panel.hidden = panel.dataset.group !== group;
      });
      const placeholder = contentEl.querySelector(".accordion-placeholder");
      if (placeholder) {
        placeholder.hidden = Boolean(group);
      }
    }

    function highlightSelection() {
      contentEl.querySelectorAll(".script-link").forEach((btn) => {
        const isDoc =
          mode === "docs" &&
          btn.dataset.path === activeDocPath &&
          !btn.dataset.section;
        const isSection =
          mode === "case-study" &&
          btn.dataset.path === activeDocPath &&
          btn.dataset.section === activeSectionId;
        btn.classList.toggle("active", Boolean(isDoc || isSection));
      });
    }

    function scrollToSection(sectionId) {
      if (!sectionId || !markdownEl) {
        return;
      }
      const target = markdownEl.querySelector(`#${CSS.escape(sectionId)}`);
      if (target) {
        target.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    }

    async function showDoc(path, sectionId) {
      activeDocPath = path;
      activeSectionId = sectionId || null;
      highlightSelection();

      let doc = cache.get(path);
      if (!doc) {
        markdownEl.innerHTML = '<p class="docs-placeholder">Loading…</p>';
        const res = await fetch(
          `/api/docs/content?path=${encodeURIComponent(path)}`
        );
        const payload = await res.json();
        if (!payload.ok || !payload.doc) {
          markdownEl.innerHTML = `<p class="docs-placeholder">${escapeHtml(
            (payload.error && payload.error.message) || "Failed to load"
          )}</p>`;
          return;
        }
        doc = payload.doc;
        cache.set(path, doc);
      }

      if (toolbarEl) {
        toolbarEl.hidden = false;
      }
      if (titleEl) {
        titleEl.textContent = doc.title || path;
      }
      if (pathEl) {
        pathEl.textContent = `Documentation/${doc.path}`;
      }

      markdownEl.innerHTML = renderMarkdown(doc.markdown);

      // In-doc Menu / relative .md links
      markdownEl.querySelectorAll("a[href]").forEach((anchor) => {
        const href = anchor.getAttribute("href") || "";
        if (href.startsWith("#")) {
          anchor.addEventListener("click", (event) => {
            event.preventDefault();
            const id = href.slice(1);
            activeSectionId = id;
            highlightSelection();
            scrollToSection(id);
          });
          return;
        }
        if (href.endsWith(".md") || href.endsWith(".MD")) {
          // leave as-is for now (external-ish relative); no dashboard route
        }
      });

      requestAnimationFrame(() => {
        if (sectionId) {
          scrollToSection(sectionId);
        } else {
          markdownEl.scrollTop = 0;
        }
      });
    }

    function createDocButton(doc) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "script-link";
      btn.dataset.path = doc.path;
      btn.innerHTML = `
        <span class="name">${escapeHtml(doc.title)}</span>
        <span class="desc">${escapeHtml(doc.path)}</span>
      `;
      btn.addEventListener("click", () => {
        showDoc(doc.path, null);
      });
      return btn;
    }

    function createSectionButton(docPath, section) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "script-link section-link";
      btn.dataset.path = docPath;
      btn.dataset.section = section.id;
      btn.innerHTML = `
        <span class="name">${escapeHtml(section.title)}</span>
      `;
      btn.addEventListener("click", () => {
        showDoc(docPath, section.id);
      });
      return btn;
    }

    async function buildCaseStudyPanels(docs) {
      contentEl.innerHTML =
        '<p class="accordion-placeholder">Select a section</p>';
      navEl.innerHTML = "";

      for (const doc of docs) {
        const res = await fetch(
          `/api/docs/content?path=${encodeURIComponent(doc.path)}`
        );
        const payload = await res.json();
        if (!payload.ok || !payload.doc) {
          continue;
        }
        cache.set(doc.path, payload.doc);
        const sections = payload.doc.sections || [];
        const groupKey = doc.path;

        const tab = document.createElement("button");
        tab.type = "button";
        tab.className = "accordion-tab";
        tab.dataset.group = groupKey;
        tab.setAttribute("aria-expanded", "false");
        tab.innerHTML = `
          <span class="accordion-label">${escapeHtml(doc.title)}</span>
          <span class="accordion-count">${sections.length}</span>
        `;
        tab.addEventListener("click", () => {
          if (activeGroup === groupKey) {
            setActiveGroup(null);
            return;
          }
          setActiveGroup(groupKey);
        });
        navEl.appendChild(tab);

        const panel = document.createElement("div");
        panel.className = "accordion-panel";
        panel.dataset.group = groupKey;
        panel.hidden = true;
        const list = document.createElement("ul");
        list.className = "script-list";
        for (const section of sections) {
          const li = document.createElement("li");
          li.appendChild(createSectionButton(doc.path, section));
          list.appendChild(li);
        }
        panel.appendChild(list);
        contentEl.appendChild(panel);
      }

      if (docs.length === 1) {
        setActiveGroup(docs[0].path);
        const first = cache.get(docs[0].path);
        const firstSection =
          first && first.sections && first.sections[0]
            ? first.sections[0].id
            : null;
        await showDoc(docs[0].path, firstSection);
      }
    }

    function buildDocsPanels(docs) {
      const grouped = groupBy(docs, (d) => d.group || "(root)");
      navEl.innerHTML = "";
      contentEl.innerHTML =
        '<p class="accordion-placeholder">Select a section</p>';

      for (const [group, items] of grouped) {
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
        navEl.appendChild(tab);

        const panel = document.createElement("div");
        panel.className = "accordion-panel";
        panel.dataset.group = group;
        panel.hidden = true;
        const list = document.createElement("ul");
        list.className = "script-list";
        for (const doc of items) {
          const li = document.createElement("li");
          li.appendChild(createDocButton(doc));
          list.appendChild(li);
        }
        panel.appendChild(list);
        contentEl.appendChild(panel);
      }
    }

    async function load() {
      if (loaded) {
        return;
      }
      loaded = true;
      configureMarked();
      try {
        const res = await fetch(listUrl);
        const payload = await res.json();
        const docs = (payload && payload.docs) || [];
        if (!docs.length) {
          if (mode === "case-study") {
            contentEl.innerHTML =
              '<p class="accordion-placeholder">No case study found</p>';
            markdownEl.innerHTML =
              '<p class="docs-placeholder">No case study found</p>';
          } else {
            contentEl.innerHTML =
              '<p class="accordion-placeholder">No documents found</p>';
            markdownEl.innerHTML =
              '<p class="docs-placeholder">Nothing under Documentation/</p>';
          }
          return;
        }
        if (mode === "case-study") {
          await buildCaseStudyPanels(docs);
        } else {
          buildDocsPanels(docs);
        }
      } catch (err) {
        loaded = false;
        markdownEl.innerHTML = `<p class="docs-placeholder">${escapeHtml(
          err.message || "Failed to load"
        )}</p>`;
      }
    }

    return { load };
  }

  const docsViewer = createDocsViewer({
    listUrl: "/api/docs",
    navEl: document.getElementById("docs-accordion-nav"),
    contentEl: document.getElementById("docs-accordion-content"),
    markdownEl: document.getElementById("docs-markdown"),
    toolbarEl: document.getElementById("docs-toolbar"),
    titleEl: document.getElementById("docs-title"),
    pathEl: document.getElementById("docs-path"),
    mode: "docs",
  });

  const caseViewer = createDocsViewer({
    listUrl: "/api/case-studies",
    navEl: document.getElementById("case-accordion-nav"),
    contentEl: document.getElementById("case-accordion-content"),
    markdownEl: document.getElementById("case-markdown"),
    toolbarEl: document.getElementById("case-toolbar"),
    titleEl: document.getElementById("case-title"),
    pathEl: document.getElementById("case-path"),
    mode: "case-study",
  });

  window.DocsDash = {
    onView(view) {
      if (view === "docs") {
        docsViewer.load();
      } else if (view === "case-study") {
        caseViewer.load();
      }
    },
  };
})();
