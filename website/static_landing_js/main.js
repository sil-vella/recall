(function () {
  var y = document.getElementById("year");
  if (y) y.textContent = String(new Date().getFullYear());

  var STORE_IOS =
    "https://apps.apple.com/us/app/dutch-card-game/id6772967073";
  var STORE_ANDROID =
    "https://play.google.com/store/apps/details?id=com.reignofplay.dutch";
  var PACKAGE = "com.reignofplay.dutch";

  function ua() {
    return navigator.userAgent || "";
  }

  function isAndroid() {
    return /Android/i.test(ua());
  }

  function isIOS() {
    return /iPhone|iPad|iPod/i.test(ua()) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  }

  window.dutchBonusHttpsPath = function (code) {
    code = String(code || "").trim().toUpperCase();
    if (!code || code === "INDEX.HTML") return "/gotoapp/";
    return "/gotoapp/" + encodeURIComponent(code);
  };

  window.dutchBonusHttpsUrl = function (code) {
    return "https://dutch.reignofplay.com" + window.dutchBonusHttpsPath(code);
  };

  /** Custom scheme (iOS same-site Safari cannot use Universal Links). */
  window.dutchBonusSchemeUrl = function (code) {
    code = String(code || "").trim().toUpperCase();
    if (!code || code === "INDEX.HTML") return "";
    return "dutch://gotoapp/" + encodeURIComponent(code);
  };

  /**
   * Best href to open the installed app from the landing / fallback page.
   * - iOS: dutch:// (required from same-host Safari)
   * - Android: intent:// with Play Store / HTTPS fallback
   * - other: HTTPS App Link path
   */
  window.dutchBonusOpenHref = function (code) {
    code = String(code || "").trim().toUpperCase();
    if (!code || code === "INDEX.HTML") return "/gotoapp/";

    var https = window.dutchBonusHttpsUrl(code);
    var scheme = window.dutchBonusSchemeUrl(code);

    if (isAndroid()) {
      return (
        "intent://gotoapp/" +
        encodeURIComponent(code) +
        "#Intent;scheme=dutch;package=" +
        PACKAGE +
        ";S.browser_fallback_url=" +
        encodeURIComponent(https) +
        ";end"
      );
    }

    if (isIOS()) {
      return scheme;
    }

    return https;
  };

  /**
   * After attempting to open the app: only leave the page if still visible.
   * Do NOT fall back to same-site /gotoapp on iOS — Safari will not hand that
   * off as a Universal Link, so users get stuck on the HTML fallback.
   * iOS fallback → App Store. Android intent already embeds its own fallback.
   */
  window.dutchScheduleOpenFallback = function (code, opts) {
    opts = opts || {};
    if (isAndroid()) return; // intent:// handles fallback

    var delayMs = typeof opts.fallbackDelayMs === "number" ? opts.fallbackDelayMs : 2000;
    var store = isIOS() ? STORE_IOS : window.dutchBonusHttpsUrl(code);

    window.setTimeout(function () {
      if (document.hidden) return;
      window.location.href = store;
    }, delayMs);
  };

  // Back-compat alias used by older inline scripts
  window.dutchScheduleHttpsFallback = window.dutchScheduleOpenFallback;
})();
