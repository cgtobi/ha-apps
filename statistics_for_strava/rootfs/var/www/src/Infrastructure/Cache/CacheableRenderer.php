<?php

declare(strict_types=1);

namespace App\Infrastructure\Cache;

use App\Infrastructure\Cache\Context\CacheContextRegistry;
use App\Infrastructure\Cache\Render\Render;
use App\Infrastructure\Cache\Render\RenderCache;
use Symfony\Component\HttpFoundation\RequestStack;

/*
 * OVERRIDDEN UPSTREAM FILE — resync on every image bump.
 *
 * Same as upstream except the cache key gets an extra segment for the current
 * request's base URL.
 *
 * v5.2.0 renders pages and fragments per request and caches the HTML. That HTML
 * is not base-path neutral here: UrlTwigExtension prefixes every relativeUrl()
 * with the request base URL, and IndexPage embeds it in window.dreeve. Under
 * Home Assistant ingress that base URL contains a per-session token
 * (/api/hassio_ingress/<token>), so a single cache entry would hand the first
 * session's token to every later session — every link, fragment fetch and asset
 * URL pointing at an expired ingress session.
 *
 * Keying per base URL keeps entries session-correct. Entries for retired tokens
 * simply go unused; the pool lives in the container layer
 * (%kernel.project_dir%/build/cache) and is discarded on restart.
 */
final readonly class CacheableRenderer
{
    public function __construct(
        private RenderCache $renderCache,
        private CacheContextRegistry $cacheContextRegistry,
        // Optional so upstream's own tests, which construct this class with the
        // two arguments above, keep working.
        private ?RequestStack $requestStack = null,
    ) {
    }

    public function render(Cacheable $cacheable): Render
    {
        $cacheability = $cacheable->getCacheability();

        return $this->renderCache->get(
            cacheKey: $cacheability->getCacheKey()
                .$this->cacheContextRegistry->buildCacheKeySegments($cacheability->getCacheContexts())
                .$this->buildBaseUrlCacheKeySegment(),
            cacheability: $cacheability,
            callback: fn (): ?string => $cacheable->render(),
        );
    }

    /**
     * Empty on direct :8080 access and on CLI, so those keep upstream's keys and
     * share one cache entry. Hashed because the raw base URL carries characters
     * RenderCache has to scrub out of a cache key anyway.
     */
    private function buildBaseUrlCacheKeySegment(): string
    {
        $baseUrl = rtrim($this->requestStack?->getCurrentRequest()?->getBaseUrl() ?? '', '/');
        if ('' === $baseUrl) {
            return '';
        }

        return sprintf('.basePath=%s', substr(hash('xxh128', $baseUrl), 0, 12));
    }
}
