<?php

declare(strict_types=1);

namespace App\Infrastructure\Twig;

use App\Application\AppUrl;
use App\Domain\Activity\Activity;
use App\Domain\Activity\ActivityFragmentPath;
use App\Domain\Activity\ActivityId;
use App\Domain\Activity\SportType\SportType;
use App\Domain\Image\ImageOrientation;
use App\Domain\Segment\Segment;
use App\Domain\Segment\SegmentFragmentPath;
use App\Infrastructure\Http\Fragment\FragmentType;
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
 * byte-identical to upstream: they carry the URLs the SPA fetches, and a stale
 * copy silently drops Twig functions templates call (v5.2.3 added filteredUrl;
 * v5.3.0 added fragmentDataUrl, fragmentPartialUrl and activityFragmentPath;
 * v5.3.3 added relativeUrlWithRedirectTo and redirectUrl) or points the app at
 * routes that no longer exist.
 *
 * The fragment*Url() functions build their path with the Symfony URL generator,
 * which already prepends the forwarded prefix, and then hand it to relativeUrl().
 * prefixWithRequestBaseUrl() returns such a URL untouched, so it is prefixed once.
 *
 * relativeUrl() builds root-absolute URLs from APP_URL's base path. Under Home
 * Assistant ingress the base path is not in APP_URL at all: it is a per-session
 * /api/hassio_ingress/<token> prefix the supervisor proxy strips and forwards as
 * X-Ingress-Path, which the Caddyfile maps to X-Forwarded-Prefix. APP_URL is
 * only a placeholder (http://localhost:8080), so getBasePath() is null and
 * relativeUrl() emits bare root-absolute paths.
 *
 * Calls that wrap path()/asset() are unaffected — Symfony's URL generator and
 * asset packages already prepend the forwarded prefix — but the literal-path
 * calls are not, and the browser resolves them against the Home Assistant host
 * root instead of the ingress base. That covers the admin "Return to app" link,
 * every top-nav href (which is also what the SPA router matches routes against),
 * the js-dist-url meta the webpack public path is read from, and the activity /
 * segment fragment links.
 *
 * relativeUrlWithRedirectTo() gets both its arguments as literal paths from
 * html/navigation/admin-edit-link.html.twig ('admin/settings/dashboard' with
 * redirectTo 'dashboard', and the like), so both need the prefix; the admin
 * activity overview passes path() output for both, which already carries it and
 * is left alone. The redirectTo value is not just a link the browser resolves:
 * the app redirects to it verbatim after the edit, so a value without the prefix
 * would land outside the ingress session.
 *
 * redirectUrl() is deliberately upstream-identical. It reads the redirectTo
 * query parameter back out, which relativeUrlWithRedirectTo() already wrote with
 * the prefix, and its callers' defaults are relativeUrl()/path() output that
 * carries it too. Prefixing here would also turn the empty default of
 * `redirectUrl('')` into a non-empty URL, and the settings forms read that as
 * "no redirect after saving" (data-redirect).
 *
 * The prefix ends up in rendered HTML that the v5.2.0 render cache stores, so
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

    #[AsTwigFunction('fragmentDataUrl')]
    public function toFragmentDataUrl(string $path): string
    {
        return $this->toRelativeUrl($this->urlGenerator->generate('api_fragment', [
            'type' => FragmentType::DATA->value,
            'path' => $path,
        ]));
    }

    #[AsTwigFunction('fragmentPartialUrl')]
    public function toFragmentPartialUrl(string $path): string
    {
        return $this->toRelativeUrl($this->urlGenerator->generate('api_fragment', [
            'type' => FragmentType::PARTIAL->value,
            'path' => $path,
        ]));
    }

    #[AsTwigFunction('activityFragmentPath')]
    public function activityFragmentPath(ActivityId $activityId, ?string $subResource = null): string
    {
        return ActivityFragmentPath::for($activityId, $subResource);
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
            '<a href="%s" data-router-link class="flex items-center gap-x-1 font-medium text-blue-600 hover:underline">%s<span class="%s">%s</span></a>',
            $this->toRelativeUrl(ActivityFragmentPath::for($activity->getId())),
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
            '<a href="%s" data-router-link class="flex items-center gap-x-1 font-medium text-blue-600 hover:underline">%s<span class="truncate">%s</span></a>',
            $this->toRelativeUrl(SegmentFragmentPath::for($segment->getId())),
            $segmentIcon,
            $this->stringTwigExtension->doEllipses((string) $segmentTitle, 50)
        );
    }
}
