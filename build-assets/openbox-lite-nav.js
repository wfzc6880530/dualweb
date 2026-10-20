(() => {
  "use strict";
  const allowLabel = /^(overview|dashboard|概览|总览|proxy|proxies|代理(?:组)?|rule|rules|规则)$/i;
  const allowPath = /\/(overview|dashboard|proxy|proxies|rules?)(\/|$)/i;
  const navRoots = 'nav, aside, [role="navigation"], [class*="sidebar"], [class*="sider"], [class*="navigation"], [class*="nav-menu"], [class*="menu-list"]';
  const hide = (el) => {
    const item = el.closest('li, [role="menuitem"], .ant-menu-item, .el-menu-item, [class*="menu-item"], [class*="nav-item"]') || el;
    item.classList.add('dualweb-openbox-lite-hidden');
  };
  const label = (el) => (el.innerText || el.textContent || el.getAttribute('aria-label') || el.getAttribute('title') || '').replace(/\s+/g, ' ').trim();
  const apply = () => {
    document.querySelectorAll(navRoots + ' a, ' + navRoots + ' button, ' + navRoots + ' [role="menuitem"]').forEach((el) => {
      const text = label(el);
      const href = el.getAttribute('href') || '';
      if (!text && !href) return;
      if (allowLabel.test(text) || allowPath.test(href)) return;
      hide(el);
    });
    document.querySelectorAll('header a, header button, [class*="header"] a, [class*="header"] button, [role="banner"] a, [role="banner"] button').forEach((el) => {
      const text = label(el);
      if (/(settings?|配置|设置|订阅|subscription|logs?|日志|about|关于|system settings|系统设置)/i.test(text)) hide(el);
    });
  };
  const start = () => {
    apply();
    const observer = new MutationObserver(() => apply());
    observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['href', 'aria-label', 'title'] });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();