(() => {
  "use strict";

  const HIDDEN = "dualweb-openbox-lite-hidden";
  // [OPENBOX-LITE-NAV] Use an allowlist so unknown upstream menu labels do not leak into the lite UI.
  const allowed = /^(概览|总览|overview|dashboard|代理|proxy|proxies|规则|rules?)$/i;
  const roots = "nav, aside, [role='navigation'], .sidebar";

  function textOf(el) {
    return (el.innerText || el.textContent || el.getAttribute("aria-label") || el.getAttribute("title") || "")
      .replace(/\s+/g, " ")
      .replace(/[（(]\d+[）)]/g, "")
      .trim();
  }

  function apply() {
    // Recovery guard: these are structural containers, never hide them.
    document.querySelectorAll(".home-page, .sidebar, #app, #app-content").forEach(el => {
      el.classList.remove(HIDDEN);
    });

    document.querySelectorAll(roots).forEach(root => {
      root.querySelectorAll("a, button, [role='menuitem']").forEach(el => {
        const label = textOf(el);
        if (!label || allowed.test(label)) return;

        const item = el.closest(
          "li, [role='menuitem'], .ant-menu-item, .el-menu-item, " +
          "[class*='menu-item'], [class*='nav-item']"
        ) || el;

        // Never hide a structural container or an element containing one.
        if (item.matches(".home-page, .sidebar, #app, #app-content")) return;
        if (item.querySelector(".home-page, .sidebar, #app, #app-content")) return;
        item.classList.add(HIDDEN);
      });
    });
  }

  function start() {
    apply();
    let queued = false;
    const observer = new MutationObserver(() => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(() => {
        queued = false;
        apply();
      });
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
