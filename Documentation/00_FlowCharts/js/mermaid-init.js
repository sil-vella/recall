/**
 * Shared Mermaid initialization for all flowchart chart pages.
 * Load after mermaid.min.js. Renders all elements with class "mermaid".
 */
(function () {
  'use strict';
  function run() {
    if (typeof mermaid === 'undefined') return;
    mermaid.initialize({
      startOnLoad: false,
      theme: 'base',
      securityLevel: 'loose',
      htmlLabels: false,
      themeVariables: {
        background: '#f4f4f4',
        primaryColor: '#fff',
        primaryTextColor: '#111',
        primaryBorderColor: '#333',
        secondaryColor: '#f0f0f0',
        secondaryTextColor: '#111',
        tertiaryColor: '#e8e8e8',
        tertiaryTextColor: '#111',
        textColor: '#111',
        nodeTextColor: '#111',
        titleColor: '#111',
        lineColor: '#333',
        mainBkg: '#fff',
        nodeBkg: '#fff'
      }
    });
    mermaid.init(undefined, document.querySelectorAll('.mermaid'));
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }
})();
