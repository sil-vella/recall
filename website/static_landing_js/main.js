(function () {
  var y = document.getElementById("year");
  if (y) y.textContent = String(new Date().getFullYear());

  /**
   * Build custom-scheme URL: dutch://gotoapp/<CODE>
   * iOS Safari will not open custom schemes from hidden iframes — the bonus
   * button must navigate top-level (native <a href> or location.href).
   */
  window.dutchBonusSchemeUrl = function (code) {
    code = String(code || "").trim().toUpperCase();
    if (!code || code === "INDEX.HTML") return "";
    return "dutch://gotoapp/" + encodeURIComponent(code);
  };

  window.dutchBonusHttpsPath = function (code) {
    code = String(code || "").trim().toUpperCase();
    if (!code || code === "INDEX.HTML") return "/gotoapp/";
    return "/gotoapp/" + encodeURIComponent(code);
  };

  /**
   * After a top-level dutch:// navigation attempt, fall back to HTTPS if the
   * page is still visible (app did not take over).
   */
  window.dutchScheduleHttpsFallback = function (code, opts) {
    opts = opts || {};
    var delayMs = typeof opts.fallbackDelayMs === "number" ? opts.fallbackDelayMs : 1500;
    var httpsPath = window.dutchBonusHttpsPath(code);
    window.setTimeout(function () {
      if (document.hidden) return;
      window.location.href = httpsPath;
    }, delayMs);
  };
})();
