/* ingress-api-shim.js
 * Force root-absolute API calls to stay under the current ingress base path.
 */
(function () {
  var HEATMAP_DIRECT_RELOAD_GUARD_KEY = "sfs_heatmap_direct_reload_once";
  var HEATMAP_INGRESS_RELOAD_GUARD_KEY = "sfs_heatmap_ingress_reload_once";
  var HEATMAP_TIMEOUT_RELOAD_GUARD_KEY = "sfs_heatmap_timeout_reload_once";
  var heatmapHealScheduled = false;
  var heatmapTimeoutCheckScheduled = false;
  var heatmapFallbackMountRunning = false;
  var heatmapHealAttempts = 0;
  var MAX_HEATMAP_HEAL_ATTEMPTS = 6;
  function isIngressContext() {
    var path = (window.location && window.location.pathname) || "";
    var host = (window.location && window.location.host) || "";
    var port = (window.location && window.location.port) || "";
    if (port === "8080") {
      return false;
    }
    if (path.indexOf("/api/hassio_ingress/") !== -1) {
      return true;
    }
    if (path.indexOf("/app/") === 0) {
      return true;
    }
    if (path.indexOf("_statistics_for_strava") !== -1) {
      return true;
    }
    if (host.indexOf(".ui.nabu.casa") !== -1) {
      return true;
    }
    return false;
  }

  function isDirectHeatmapPath() {
    var path = (window.location && window.location.pathname) || "";
    return /\/heatmap\/?$/.test(path);
  }
  function normalize(url) {
    if (typeof url !== "string") {
      return url;
    }
    if (url.indexOf("/api./") === 0) {
      url = "/api/" + url.substring(6);
    }
    if (url.indexOf("/api/hassio_ingress/") === 0) {
      return url;
    }
    if (url.indexOf("api./") === 0) {
      return "./api/" + url.substring(5);
    }
    // Normalize app-relative route fragments that miss "./" prefix.
    if (
      url.indexOf("api/") === 0 ||
      url.indexOf("activity/") === 0 ||
      url.indexOf("segment/") === 0 ||
      url.indexOf("heatmap/") === 0 ||
      url.indexOf("month/") === 0
    ) {
      return "./" + url;
    }
    // Generic ingress-safe normalization for root-absolute in-app requests.
    if (url.indexOf("/") === 0 && url.indexOf("//") !== 0) {
      return "." + url;
    }
    try {
      var origin = window.location && window.location.origin ? window.location.origin : "";
      if (origin && url.indexOf(origin + "/api./") === 0) {
        url = origin + "/api/" + url.substring((origin + "/api./").length);
      }
      if (origin && url.indexOf(origin + "/api/hassio_ingress/") === 0) {
        return url;
      }
      if (origin && url.indexOf(origin + "/") === 0) {
        return "." + url.substring(origin.length);
      }
    } catch (_e) {
      // Keep original URL on parse failures.
    }
    return url;
  }

  var originalFetch = window.fetch;
  if (typeof originalFetch === "function") {
    window.fetch = function (input, init) {
      if (typeof input === "string") {
        input = normalize(input);
      } else if (typeof Request !== "undefined" && input instanceof Request) {
        var mapped = normalize(input.url);
        if (mapped !== input.url) {
          input = new Request(mapped, input);
        }
      }
      return originalFetch.call(this, input, init);
    };
  }

  var originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    if (typeof url === "string") {
      url = normalize(url);
    }
    var args = Array.prototype.slice.call(arguments);
    args[1] = url;
    return originalOpen.apply(this, args);
  };

  if (typeof window.EventSource === "function") {
    var NativeEventSource = window.EventSource;
    window.EventSource = function (url, config) {
      return new NativeEventSource(normalize(url), config);
    };
    window.EventSource.prototype = NativeEventSource.prototype;
  }

  function rewriteHeatmapAnchors() {
    if (!isIngressContext()) {
      return;
    }
    var anchors = document.querySelectorAll("a[href]");
    for (var i = 0; i < anchors.length; i += 1) {
      var a = anchors[i];
      var href = a.getAttribute("href");
      if (!href) {
        continue;
      }
      if (href === "/heatmap" || href === "/heatmap/" || href === "heatmap" || href === "heatmap/") {
        a.setAttribute("href", "./heatmap");
      }
    }
  }

  function remapHeatmapNavUrl(url) {
    if (!isIngressContext() || typeof url !== "string" || !url) {
      return url;
    }
    try {
      var u = new URL(url, window.location.href);
      if (/\/heatmap\/?$/.test(u.pathname) && u.hash.indexOf("heatmap") === -1) {
        return "./heatmap";
      }
    } catch (_e) {
      if (url === "/heatmap" || url === "/heatmap/" || url === "heatmap" || url === "heatmap/") {
        return "./heatmap";
      }
    }
    return url;
  }

  function installHeatmapHistoryRemap() {
    if (!isIngressContext()) {
      return;
    }
    var originalPushState = window.history && window.history.pushState;
    if (typeof originalPushState === "function") {
      window.history.pushState = function (state, title, url) {
        if (typeof url === "string") {
          url = remapHeatmapNavUrl(url);
        }
        return originalPushState.call(this, state, title, url);
      };
    }
    var originalReplaceState = window.history && window.history.replaceState;
    if (typeof originalReplaceState === "function") {
      window.history.replaceState = function (state, title, url) {
        if (typeof url === "string") {
          url = remapHeatmapNavUrl(url);
        }
        return originalReplaceState.call(this, state, title, url);
      };
    }
  }

  function installHeatmapClickFallback() {
    if (!isIngressContext()) {
      return;
    }
    document.addEventListener(
      "click",
      function (evt) {
        var node = evt.target;
        while (node && node !== document.body) {
          if (node.tagName === "A") {
            return;
          }
          var text = (node.textContent || "").trim().toLowerCase();
          var attrHref = ((node.getAttribute && node.getAttribute("href")) || "").toLowerCase();
          var attrTo = ((node.getAttribute && node.getAttribute("to")) || "").toLowerCase();
          var attrRoute = ((node.getAttribute && node.getAttribute("data-route")) || "").toLowerCase();
          var attrNav = ((node.getAttribute && node.getAttribute("data-nav")) || "").toLowerCase();
          var attrTestId = ((node.getAttribute && node.getAttribute("data-testid")) || "").toLowerCase();
          var attrAria = ((node.getAttribute && node.getAttribute("aria-label")) || "").toLowerCase();
          var attrTitle = ((node.getAttribute && node.getAttribute("title")) || "").toLowerCase();
          var attrOnclick = ((node.getAttribute && node.getAttribute("onclick")) || "").toLowerCase();

          var isHeatmapIntent =
            text.indexOf("heatmap") !== -1 ||
            attrHref.indexOf("heatmap") !== -1 ||
            attrTo.indexOf("heatmap") !== -1 ||
            attrRoute.indexOf("heatmap") !== -1 ||
            attrNav.indexOf("heatmap") !== -1 ||
            attrTestId.indexOf("heatmap") !== -1 ||
            attrAria.indexOf("heatmap") !== -1 ||
            attrTitle.indexOf("heatmap") !== -1 ||
            attrOnclick.indexOf("heatmap") !== -1;

          if (isHeatmapIntent) {
            var beforeHref = window.location.href;
            setTimeout(function () {
              if (window.location.href === beforeHref && window.location.pathname.indexOf("/heatmap") === -1) {
                window.location.assign("./heatmap");
              }
            }, 120);
            return;
          }
          node = node.parentElement;
        }
      },
      true
    );
  }

  function looksLikeHeatmapRoute() {
    var path = (window.location && window.location.pathname) || "";
    var hash = (window.location && window.location.hash) || "";
    return path.indexOf("/heatmap") !== -1 || hash.indexOf("heatmap") !== -1;
  }

  function hasMountedHeatmap() {
    var hm = document.querySelector("#heatmap");
    return !!(hm && hm.children && hm.children.length > 0);
  }

  function parseHeatmapConfig(el) {
    var raw = (el && el.getAttribute && el.getAttribute("data-heatmap-config")) || "{}";
    try {
      var parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object") {
        return parsed;
      }
    } catch (_e) {}
    return {};
  }

  function toLatLng(value) {
    if (Array.isArray(value) && value.length >= 2) {
      var latA = Number(value[0]);
      var lngA = Number(value[1]);
      if (Number.isFinite(latA) && Number.isFinite(lngA)) {
        return [latA, lngA];
      }
    }
    if (value && typeof value === "object") {
      var latB = Number(value.lat != null ? value.lat : value.latitude);
      var lngB = Number(
        value.lng != null ? value.lng : value.lon != null ? value.lon : value.longitude
      );
      if (Number.isFinite(latB) && Number.isFinite(lngB)) {
        return [latB, lngB];
      }
    }
    return null;
  }

  function maybeFallbackMountHeatmap() {
    if (heatmapFallbackMountRunning) {
      return;
    }
    if (!looksLikeHeatmapRoute()) {
      return;
    }
    var el = document.querySelector("#heatmap");
    if (!el) {
      return;
    }
    if (el.querySelector(".leaflet-container")) {
      return;
    }
    if (el.getAttribute("data-sfs-heatmap-fallback") === "done") {
      return;
    }
    if (!window.L || typeof window.L.map !== "function") {
      return;
    }

    heatmapFallbackMountRunning = true;
    var routesUrl = el.getAttribute("data-leaflet-routes") || "./api/heatmap/routes.json";
    var cfg = parseHeatmapConfig(el);
    var tileUrls = Array.isArray(cfg.tileLayerUrls) && cfg.tileLayerUrls.length > 0
      ? cfg.tileLayerUrls
      : ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"];
    var polylineColor = typeof cfg.polylineColor === "string" && cfg.polylineColor
      ? cfg.polylineColor
      : "#fc6719";

    fetch(routesUrl)
      .then(function (r) {
        if (!r.ok) {
          throw new Error("heatmap routes fetch failed: " + r.status);
        }
        return r.json();
      })
      .then(function (routes) {
        if (!Array.isArray(routes)) {
          throw new Error("heatmap routes payload is not an array");
        }
        if (el.querySelector(".leaflet-container")) {
          el.setAttribute("data-sfs-heatmap-fallback", "done");
          return;
        }

        var map = window.L.map(el, { preferCanvas: true, zoomControl: true });
        window.L.tileLayer(tileUrls[0], {
          maxZoom: 19,
          attribution: "&copy; OpenStreetMap contributors",
        }).addTo(map);

        var bounds = null;
        for (var i = 0; i < routes.length; i += 1) {
          var coords = routes[i] && routes[i].coordinates;
          if (!Array.isArray(coords)) {
            continue;
          }
          var line = [];
          for (var j = 0; j < coords.length; j += 1) {
            var ll = toLatLng(coords[j]);
            if (ll) {
              line.push(ll);
            }
          }
          if (line.length > 1) {
            window.L.polyline(line, {
              color: polylineColor,
              weight: 2,
              opacity: 0.55,
            }).addTo(map);

            if (!bounds) {
              bounds = window.L.latLngBounds(line[0], line[0]);
            }
            for (var k = 1; k < line.length; k += 1) {
              bounds.extend(line[k]);
            }
          }
        }

        if (bounds && bounds.isValid && bounds.isValid()) {
          map.fitBounds(bounds, { padding: [18, 18] });
        } else {
          map.setView([0, 0], 2);
        }

        el.setAttribute("data-sfs-heatmap-fallback", "done");
        setTimeout(function () {
          map.invalidateSize();
        }, 50);
      })
      .catch(function (_e) {
        // Keep runtime stable if fallback mount fails.
      })
      .finally(function () {
        heatmapFallbackMountRunning = false;
      });
  }

  function dispatchRouteLifecycleNudge() {
    try {
      if (typeof HashChangeEvent === "function") {
        window.dispatchEvent(new HashChangeEvent("hashchange"));
      } else {
        window.dispatchEvent(new Event("hashchange"));
      }
    } catch (_e0) {}
    try {
      if (typeof PopStateEvent === "function") {
        window.dispatchEvent(new PopStateEvent("popstate"));
      } else {
        window.dispatchEvent(new Event("popstate"));
      }
    } catch (_e1) {}
  }

  function maybeHealHeatmapBlankRender() {
    try {
      if (!looksLikeHeatmapRoute()) {
        return;
      }
      if (hasMountedHeatmap()) {
        heatmapHealAttempts = 0;
        heatmapTimeoutCheckScheduled = false;
        try {
          window.sessionStorage.removeItem(HEATMAP_DIRECT_RELOAD_GUARD_KEY);
          window.sessionStorage.removeItem(HEATMAP_INGRESS_RELOAD_GUARD_KEY);
          window.sessionStorage.removeItem(HEATMAP_TIMEOUT_RELOAD_GUARD_KEY);
        } catch (_eMounted) {}
        return;
      }
      if (!heatmapTimeoutCheckScheduled) {
        heatmapTimeoutCheckScheduled = true;
        setTimeout(function () {
          if (!looksLikeHeatmapRoute()) {
            return;
          }
          maybeFallbackMountHeatmap();
          if (hasMountedHeatmap()) {
            try {
              window.sessionStorage.removeItem(HEATMAP_TIMEOUT_RELOAD_GUARD_KEY);
            } catch (_eTimeoutClear) {}
            return;
          }
          setTimeout(function () {
            if (hasMountedHeatmap()) {
              try {
                window.sessionStorage.removeItem(HEATMAP_TIMEOUT_RELOAD_GUARD_KEY);
              } catch (_eTimeoutClear2) {}
              return;
            }
            try {
              var timeoutReloaded = window.sessionStorage.getItem(HEATMAP_TIMEOUT_RELOAD_GUARD_KEY);
              if (timeoutReloaded !== "1") {
                window.sessionStorage.setItem(HEATMAP_TIMEOUT_RELOAD_GUARD_KEY, "1");
                window.location.reload();
              }
            } catch (_eTimeoutReload) {}
          }, 900);
        }, 2600);
      }
      if (heatmapHealScheduled) {
        return;
      }
      heatmapHealScheduled = true;
      var tryNudge = function () {
        if (!looksLikeHeatmapRoute()) {
          heatmapHealAttempts = 0;
          heatmapHealScheduled = false;
          return;
        }
        if (hasMountedHeatmap()) {
          heatmapHealAttempts = 0;
          heatmapHealScheduled = false;
          heatmapTimeoutCheckScheduled = false;
          try {
            window.sessionStorage.removeItem(HEATMAP_DIRECT_RELOAD_GUARD_KEY);
            window.sessionStorage.removeItem(HEATMAP_INGRESS_RELOAD_GUARD_KEY);
            window.sessionStorage.removeItem(HEATMAP_TIMEOUT_RELOAD_GUARD_KEY);
          } catch (_eMounted2) {}
          return;
        }
        if (heatmapHealAttempts >= MAX_HEATMAP_HEAL_ATTEMPTS) {
          if (isIngressContext() && !window.location.hash && window.location.pathname.indexOf("/heatmap") !== -1) {
            try {
              var ingressAlready = window.sessionStorage.getItem(HEATMAP_INGRESS_RELOAD_GUARD_KEY);
              if (ingressAlready !== "1") {
                window.sessionStorage.setItem(HEATMAP_INGRESS_RELOAD_GUARD_KEY, "1");
                window.location.reload();
                return;
              }
            } catch (_eIngressReload) {}
          }
          if (!isIngressContext() && isDirectHeatmapPath()) {
            try {
              var already = window.sessionStorage.getItem(HEATMAP_DIRECT_RELOAD_GUARD_KEY);
              if (already !== "1") {
                window.sessionStorage.setItem(HEATMAP_DIRECT_RELOAD_GUARD_KEY, "1");
                window.location.reload();
                return;
              }
            } catch (_eReload) {}
          }
          heatmapHealScheduled = false;
          return;
        }
        heatmapHealAttempts += 1;
        dispatchRouteLifecycleNudge();
        setTimeout(function () {
          if (hasMountedHeatmap()) {
            heatmapHealAttempts = 0;
            heatmapHealScheduled = false;
            heatmapTimeoutCheckScheduled = false;
            try {
              window.sessionStorage.removeItem(HEATMAP_DIRECT_RELOAD_GUARD_KEY);
              window.sessionStorage.removeItem(HEATMAP_INGRESS_RELOAD_GUARD_KEY);
              window.sessionStorage.removeItem(HEATMAP_TIMEOUT_RELOAD_GUARD_KEY);
            } catch (_eMounted3) {}
            return;
          }
          setTimeout(tryNudge, 700);
        }, 250);
      };
      setTimeout(tryNudge, 300);
    } catch (_e) {
      // Keep runtime stable if self-heal checks fail.
    }
  }

  if (typeof document !== "undefined") {
    // Keep routing behavior upstream-driven; only heal rendering failures.
    rewriteHeatmapAnchors();
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", maybeHealHeatmapBlankRender, { once: true });
    } else {
      maybeHealHeatmapBlankRender();
    }
    window.addEventListener("hashchange", maybeHealHeatmapBlankRender);
    window.addEventListener("popstate", maybeHealHeatmapBlankRender);
    if (typeof MutationObserver === "function" && document.body) {
      var obs = new MutationObserver(function () {
        rewriteHeatmapAnchors();
        maybeHealHeatmapBlankRender();
      });
      obs.observe(document.body, { childList: true, subtree: true });
    }
  }

})();
