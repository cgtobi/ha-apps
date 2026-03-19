/* ingress-api-shim.js
 * Force root-absolute API calls to stay under the current ingress base path.
 */
(function () {
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
    if (url.indexOf("/api/") === 0) {
      return "." + url;
    }
    if (url.indexOf("/activity/") === 0) {
      return "." + url;
    }
    if (url.indexOf("/segment/") === 0) {
      return "." + url;
    }
    if (url.indexOf("api./") === 0) {
      return "./api/" + url.substring(5);
    }
    if (url.indexOf("activity/") === 0) {
      return "./" + url;
    }
    if (url.indexOf("segment/") === 0) {
      return "./" + url;
    }
    try {
      var origin = window.location && window.location.origin ? window.location.origin : "";
      if (origin && url.indexOf(origin + "/api./") === 0) {
        url = origin + "/api/" + url.substring((origin + "/api./").length);
      }
      if (origin && url.indexOf(origin + "/api/hassio_ingress/") === 0) {
        return url;
      }
      if (origin && url.indexOf(origin + "/api/") === 0) {
        return "." + url.substring(origin.length);
      }
      if (origin && url.indexOf(origin + "/activity/") === 0) {
        return "." + url.substring(origin.length);
      }
      if (origin && url.indexOf(origin + "/segment/") === 0) {
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
})();
