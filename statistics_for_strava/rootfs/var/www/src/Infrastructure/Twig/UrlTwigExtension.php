<?php

declare(strict_types=1);

namespace App\Infrastructure\Twig;

use App\Application\AppUrl;
use App\Domain\Activity\Activity;
use App\Domain\Activity\SportType\SportType;
use App\Domain\Image\ImageOrientation;
use App\Domain\Segment\Segment;
use App\Infrastructure\Http\Request\RedirectTo;
use App\Infrastructure\ValueObject\String\FilteredUrl;
use App\Infrastructure\ValueObject\String\RelativeUrl;
use Symfony\Component\HttpFoundation\RequestStack;
use Symfony\Component\Routing\Generator\UrlGeneratorInterface;
use Twig\Attribute\AsTwigFilter;
use Twig\Attribute\AsTwigFunction;

/*
 * OVERRIDDEN UPSTREAM FILE — resync on every image bump.
 *
 * Same as upstream except relativeUrl(), filteredUrl() and both halves of
 * relativeUrlWithRedirectTo() re-anchor their result on the current request's
 * base URL (see prefixWithRequestBaseUrl below). Keep every other method
 * byte-identical to upstream: a stale copy silently drops Twig functions
 * templates call (v5.2.3 added filteredUrl; v5.3.3 added
 * relativeUrlWithRedirectTo and redirectUrl; v5.4.4 added absoluteUrl; v5.6.0
 * rewrote absoluteUrl on AppUrl::withPath) or points the app at routes that no
 * longer exist. A body change like v5.6.0's slips past sfs-verify-overrides.sh's
 * literal check, so hand-diff this file against upstream on every bump.
 *
 * relativeUrl() builds root-absolute URLs from APP_URL's base path. Under Home
 * Assistant ingress the base path is not in APP_URL at all: it is a per-session
 * /api/hassio_ingress/<token> prefix the supervisor proxy strips and forwards as
 * X-Ingress-Path, which the Caddyfile maps to X-Forwarded-Prefix. APP_URL is
 * only a placeholder (http://localhost:8080), so getBasePath() is null and
 * relativeUrl() emits bare root-absolute paths.
 *
 * Calls that wrap path()/asset() are unaffected — Symfony's URL generator and
 * asset packages already prepend the forwarded prefix, and
 * prefixWithRequestBaseUrl() returns such a URL untouched, so it is prefixed
 * once — but the literal-path calls are not, and the browser resolves them
 * against the Home Assistant host root instead of the ingress base. That covers
 * the admin link and logo in the top nav, the "Return to app" link in admin, and
 * the js-dist-url meta the webpack public path is read from.
 *
 * relativeUrlWithRedirectTo() prefixes both its arguments for the same reason.
 * The redirectTo value is not just a link the browser resolves: the app
 * redirects to it verbatim after the edit, so a value without the prefix would
 * land outside the ingress session.
 *
 * redirectUrl() is deliberately upstream-identical. It reads the redirectTo
 * query parameter back out, which relativeUrlWithRedirectTo() already wrote with
 * the prefix, and its callers' defaults are relativeUrl()/path() output that
 * carries it too. Prefixing here would also turn the empty default of
 * `redirectUrl('')` into a non-empty URL, and the settings forms read that as
 * "no redirect after saving" (data-redirect).
 *
 * absoluteUrl() is for URLs read outside the app (Open Graph tags, badge embed
 * snippets), which have to be built on APP_URL. Its callers pass path() output,
 * which under ingress already carries the per-session
 * /api/hassio_ingress/<token> prefix; upstream would glue that onto APP_URL and
 * publish a URL that dies with the session. So the request base URL is stripped
 * first (see stripRequestBaseUrl below); otherwise it stays upstream-identical.
 *
 * The prefix ends up in rendered HTML that the render cache stores, so
 * CacheableRenderer is overridden as well to key cache entries per base path.
 */
final readonly class UrlTwigExtension
{
    public function __construct(
        private AppUrl $appUrl,
        private RequestStack $requestStack,
        private UrlGeneratorInterface $urlGenerator,
        private StringTwigExtension $stringTwigExtension,
        private SvgsTwigExtension $svgsTwigExtension,
    ) {
    }

    #[AsTwigFunction('relativeUrl')]
    public function toRelativeUrl(string $path): string
    {
        return $this->prefixWithRequestBaseUrl(
            RelativeUrl::from($path, $this->appUrl)->toRelativeUrl()
        );
    }

    #[AsTwigFunction('absoluteUrl')]
    public function toAbsoluteUrl(string $path): string
    {
        return (string) $this->appUrl->withPath($this->stripRequestBaseUrl($path));
    }

    #[AsTwigFunction('relativeUrlWithRedirectTo')]
    public function toRelativeUrlWithRedirectTo(string $path, string $redirectTo): string
    {
        $url = $this->prefixWithRequestBaseUrl(RelativeUrl::from($path, $this->appUrl)->toRelativeUrl());

        return $url
            .(str_contains($url, '?') ? '&' : '?')
            .RedirectTo::QUERY_PARAM
            .'='.rawurlencode($this->prefixWithRequestBaseUrl(RelativeUrl::from($redirectTo, $this->appUrl)->toRelativeUrl()));
    }

    #[AsTwigFunction('redirectUrl')]
    public function toRedirectUrl(string $default): string
    {
        if (!($request = $this->requestStack->getCurrentRequest()) instanceof \Symfony\Component\HttpFoundation\Request) {
            return $default;
        }
        $redirectTo = RedirectTo::fromRequest($request, $this->appUrl);

        return $redirectTo instanceof RedirectTo ? (string) $redirectTo : $default;
    }

    /**
     * @param array<string, mixed> $filters
     */
    #[AsTwigFunction('filteredUrl')]
    public function toFilteredUrl(string $path, array $filters): string
    {
        return $this->prefixWithRequestBaseUrl(
            FilteredUrl::from($path, $filters, $this->appUrl)->toRelativeUrl()
        );
    }

    /**
     * Prepend the current request's base URL (the reverse-proxy prefix from
     * X-Forwarded-Prefix, empty on direct :8080 access and on CLI) unless the
     * URL already carries it, which is the case for the many call sites that
     * pass path()/asset() output through relativeUrl().
     */
    private function prefixWithRequestBaseUrl(string $url): string
    {
        $baseUrl = rtrim($this->requestStack->getCurrentRequest()?->getBaseUrl() ?? '', '/');
        if ('' === $baseUrl || $url === $baseUrl || str_starts_with($url, $baseUrl.'/')) {
            return $url;
        }

        return $baseUrl.$url;
    }

    /**
     * The inverse of prefixWithRequestBaseUrl(): drop the current request's base
     * URL from the start of a path()-generated URL, so absoluteUrl() builds on
     * APP_URL alone instead of APP_URL plus the ingress session prefix.
     */
    private function stripRequestBaseUrl(string $url): string
    {
        $baseUrl = rtrim($this->requestStack->getCurrentRequest()?->getBaseUrl() ?? '', '/');
        if ('' === $baseUrl) {
            return $url;
        }
        if ($url === $baseUrl) {
            return '/';
        }
        if (str_starts_with($url, $baseUrl.'/')) {
            return substr($url, strlen($baseUrl));
        }

        return $url;
    }

    #[AsTwigFunction('placeholderImage')]
    public function placeholderImage(?ImageOrientation $imageOrientation = null): string
    {
        if (ImageOrientation::PORTRAIT === $imageOrientation) {
            return $this->toRelativeUrl('/assets/placeholder-portrait.webp');
        }

        return $this->toRelativeUrl('/assets/placeholder.webp');
    }

    #[AsTwigFilter('countryIcon')]
    public function countryIcon(string $countryCode): string
    {
        return $this->toRelativeUrl('/assets/images/flags/'.strtolower($countryCode).'.svg');
    }

    #[AsTwigFilter('activityLink', isSafe: ['html'])]
    public function renderActivityTitleLink(Activity $activity, ?int $ellipses = null, bool $truncate = false): string
    {
        $activityIcon = match (true) {
            !$activity->getSportType()->isVirtualRide() => $this->svgsTwigExtension->svgSportType($activity->getSportType()),
            $activity->isZwiftRide() => $this->svgsTwigExtension->svg('zwift-logo'),
            $activity->isRouvyRide() => $this->svgsTwigExtension->svg('rouvy-logo'),
            $activity->isMyWhooshRide() => $this->svgsTwigExtension->svg('my-whoosh-logo'),
            default => $this->svgsTwigExtension->svgSportType(SportType::RIDE),
        };

        $activityTitle = $activity->getName();

        return sprintf(
            '<a href="%s" class="flex items-center gap-x-1 font-medium text-blue-600 hover:underline">%s<span class="%s">%s</span></a>',
            $this->toRelativeUrl($this->urlGenerator->generate('activity', ['activityId' => (string) $activity->getId()])),
            $activityIcon,
            $truncate ? 'truncate' : '',
            $ellipses ? $this->stringTwigExtension->doEllipses($activityTitle, $ellipses) : $activityTitle
        );
    }

    #[AsTwigFilter('segmentLink', isSafe: ['html'])]
    public function renderSegmentTitleLink(Segment $segment): string
    {
        $segmentIcon = match (true) {
            !$segment->getSportType()->isVirtualRide() => $this->svgsTwigExtension->svgSportType($segment->getSportType()),
            $segment->isZwiftSegment() => $this->svgsTwigExtension->svg('zwift-logo'),
            $segment->isRouvySegment() => $this->svgsTwigExtension->svg('rouvy-logo'),
            $segment->isMyWhooshSegment() => $this->svgsTwigExtension->svg('my-whoosh-logo'),
            default => $this->svgsTwigExtension->svgSportType(SportType::RIDE),
        };

        $segmentTitle = $segment->getName();

        return sprintf(
            '<a href="%s" class="flex items-center gap-x-1 font-medium text-blue-600 hover:underline">%s<span class="truncate">%s</span></a>',
            $this->toRelativeUrl($this->urlGenerator->generate('segment', ['segmentId' => (string) $segment->getId()])),
            $segmentIcon,
            $this->stringTwigExtension->doEllipses((string) $segmentTitle, 50)
        );
    }
}
