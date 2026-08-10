<?php

declare(strict_types=1);

namespace App\Infrastructure\Twig;

use App\Application\AppUrl;
use App\Domain\Activity\Activity;
use App\Domain\Activity\SportType\SportType;
use App\Domain\Image\ImageOrientation;
use App\Domain\Segment\Segment;
use App\Infrastructure\ValueObject\String\RelativeUrl;
use Symfony\Component\HttpFoundation\RequestStack;
use Twig\Attribute\AsTwigFilter;
use Twig\Attribute\AsTwigFunction;

/*
 * OVERRIDDEN UPSTREAM FILE — resync on every image bump.
 *
 * Same as upstream except toRelativeUrl() re-anchors the result on the current
 * request's base URL (see prefixWithRequestBaseUrl below). Keep every other
 * method byte-identical to upstream: they carry the URLs the SPA fetches, and a
 * stale copy silently points the app at routes that no longer exist (v5.2.0 moved
 * activity/segment modals from "<id>.html" to "api/fragment/page/...").
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
 * the js-dist-url meta the webpack public path is read from, and the
 * data-model-content-url fragment URLs behind activity/segment modals.
 *
 * The prefix ends up in rendered HTML that the v5.2.0 render cache stores, so
 * CacheableRenderer is overridden as well to key cache entries per base path.
 */
final readonly class UrlTwigExtension
{
    public function __construct(
        private AppUrl $appUrl,
        private StringTwigExtension $stringTwigExtension,
        private SvgsTwigExtension $svgsTwigExtension,
        // Optional so upstream's own UrlTwigExtensionTest, which constructs this
        // class with the three arguments above, keeps working.
        private ?RequestStack $requestStack = null,
    ) {
    }

    #[AsTwigFunction('relativeUrl')]
    public function toRelativeUrl(string $path): string
    {
        return $this->prefixWithRequestBaseUrl(
            RelativeUrl::from($path, $this->appUrl)->toRelativeUrl()
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
        $baseUrl = rtrim($this->requestStack?->getCurrentRequest()?->getBaseUrl() ?? '', '/');
        if ('' === $baseUrl) {
            return $url;
        }
        if ($url === $baseUrl || str_starts_with($url, $baseUrl.'/')) {
            return $url;
        }

        return $baseUrl.$url;
    }

    #[AsTwigFunction('securedImageUrl')]
    public function securedImageUrl(string $imageUrl): string
    {
        $pathRelativeToFiles = ltrim((string) preg_replace('#^/?files/#', '', $imageUrl), '/');

        return $this->toRelativeUrl('secured-image/'.$pathRelativeToFiles);
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
            '<a href="#" data-model-content-url="%s" class="flex items-center gap-x-1 font-medium text-blue-600 hover:underline" rel="nofollow">%s<span class="%s">%s</span></a>',
            $this->toRelativeUrl('api/fragment/page/activity/'.$activity->getId()),
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
            '<a href="#" data-model-content-url="%s" class="flex items-center gap-x-1 font-medium text-blue-600 hover:underline" rel="nofollow">%s<span class="truncate">%s</span></a>',
            $this->toRelativeUrl('api/fragment/page/segment/'.$segment->getId()),
            $segmentIcon,
            $this->stringTwigExtension->doEllipses((string) $segmentTitle, 50)
        );
    }
}
