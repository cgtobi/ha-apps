/* ingress-api-shim.js
 * Force root-absolute API calls to stay under the current ingress base path.
 */
(function () {
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

  function getIngressBasePath() {
    if (!isIngressContext()) {
      return "";
    }
    var path = (window.location && window.location.pathname) || "";
    var match = path.match(/^\/api\/hassio_ingress\/[^/]+/);
    return match ? match[0] : "";
  }

  function shouldRewriteIngressAssetPath(pathname) {
    if (typeof pathname !== "string" || pathname.indexOf("/") !== 0) {
      return false;
    }
    if (pathname.indexOf("/api/hassio_ingress/") === 0) {
      return false;
    }
    if (pathname.indexOf("/js/") === 0) {
      return true;
    }
    if (pathname.indexOf("/css/") === 0) {
      return true;
    }
    if (pathname.indexOf("/libraries/") === 0) {
      return true;
    }
    if (pathname.indexOf("/assets/") === 0) {
      return true;
    }
    return false;
  }

  function normalizeAssetUrlForIngress(url) {
    if (typeof url !== "string" || !url) {
      return url;
    }
    if (!isIngressContext()) {
      return url;
    }
    var ingressBase = getIngressBasePath();
    if (!ingressBase) {
      return url;
    }
    if (url.indexOf("//") === 0 || url.indexOf("data:") === 0 || url.indexOf("blob:") === 0) {
      return url;
    }
    try {
      var parsed = new URL(url, window.location.href);
      if (parsed.origin !== window.location.origin) {
        return url;
      }
      if (!shouldRewriteIngressAssetPath(parsed.pathname)) {
        return url;
      }
      return ingressBase + parsed.pathname + parsed.search + parsed.hash;
    } catch (_e) {
      if (url.indexOf("/") === 0 && shouldRewriteIngressAssetPath(url)) {
        return ingressBase + url;
      }
    }
    return url;
  }

  function patchElementAttributeSetter(tagName, attrName) {
    var ctor =
      tagName === "script"
        ? window.HTMLScriptElement
        : tagName === "link"
          ? window.HTMLLinkElement
          : null;
    if (!ctor || !ctor.prototype) {
      return;
    }
    var descriptor = Object.getOwnPropertyDescriptor(ctor.prototype, attrName);
    if (!descriptor || typeof descriptor.set !== "function" || typeof descriptor.get !== "function") {
      return;
    }
    Object.defineProperty(ctor.prototype, attrName, {
      configurable: true,
      enumerable: descriptor.enumerable,
      get: descriptor.get,
      set: function (value) {
        return descriptor.set.call(this, normalizeAssetUrlForIngress(value));
      },
    });
  }

  function patchSetAttribute() {
    var nativeSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      var attr = typeof name === "string" ? name.toLowerCase() : "";
      if (
        (this.tagName === "SCRIPT" && attr === "src") ||
        (this.tagName === "LINK" && attr === "href")
      ) {
        value = normalizeAssetUrlForIngress(value);
      }
      return nativeSetAttribute.call(this, name, value);
    };
  }

  function patchNodeInsertion(methodName) {
    var nativeMethod = Node.prototype[methodName];
    if (typeof nativeMethod !== "function") {
      return;
    }
    Node.prototype[methodName] = function (node) {
      if (node && node.tagName === "SCRIPT" && node.src) {
        node.src = normalizeAssetUrlForIngress(node.src);
      } else if (node && node.tagName === "LINK" && node.href) {
        node.href = normalizeAssetUrlForIngress(node.href);
      }
      return nativeMethod.apply(this, arguments);
    };
  }

  function installIngressAssetDomPatches() {
    patchElementAttributeSetter("script", "src");
    patchElementAttributeSetter("link", "href");
    patchSetAttribute();
    patchNodeInsertion("appendChild");
    patchNodeInsertion("insertBefore");
  }

  installIngressAssetDomPatches();

  // Seed the ingress base path into upstream's runtime config before app.min.js
  // reads it. Upstream derives basePath at build time from appUrl, which is
  // unknown for the dynamic HA ingress prefix (/api/hassio_ingress/<token>/),
  // so it ships basePath="". That breaks router page-name dispatch
  // (page === 'heatmap' never matches on direct load/reload) and the webpack
  // public path for dynamic chunks. The inline assignment
  // `window.statisticsForStrava = {...}` runs after this shim, so intercept it
  // via a defineProperty setter and patch appUrl.basePath on assignment.
  (function seedIngressBasePath() {
    if (!isIngressContext()) {
      return;
    }
    var ingressBase = getIngressBasePath();
    if (!ingressBase) {
      return;
    }
    var basePathValue = ingressBase.replace(/^\/+/, "");
    var pending;
    try {
      Object.defineProperty(window, "statisticsForStrava", {
        configurable: true,
        enumerable: true,
        get: function () {
          return pending;
        },
        set: function (value) {
          if (value && value.appUrl && typeof value.appUrl === "object") {
            value.appUrl.basePath = basePathValue;
          }
          pending = value;
        },
      });
    } catch (_e) {
      // If the property is already defined/non-configurable, patch in place.
      try {
        if (
          window.statisticsForStrava &&
          window.statisticsForStrava.appUrl &&
          typeof window.statisticsForStrava.appUrl === "object"
        ) {
          window.statisticsForStrava.appUrl.basePath = basePathValue;
        }
      } catch (_e2) {}
    }
  })();

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
})();
