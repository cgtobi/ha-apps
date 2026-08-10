<?php

declare(strict_types=1);

namespace App\Application;

use App\Domain\Activity\ActivityIdRepository;
use App\Domain\Activity\BestEffort\ActivityBestEffortRepository;
use App\Domain\Activity\Image\ImageRepository;
use App\Domain\Challenge\ChallengeRepository;
use App\Domain\Gear\GearRepository;
use App\Domain\Settings\SettingsRepository;
use App\Infrastructure\Cache\Cacheability;
use App\Infrastructure\Cache\Cacheable;
use App\Infrastructure\Cache\Tag\CacheTags;
use App\Infrastructure\Cache\Tag\RootCacheTag;
use App\Infrastructure\Serialization\Json;
use Symfony\Component\HttpFoundation\RequestStack;
use Symfony\Component\Intl\Countries;
use Symfony\Component\Translation\LocaleSwitcher;
use Twig\Environment;

/*
 * OVERRIDDEN UPSTREAM FILE — resync on every image bump.
 *
 * Same as upstream except appUrl.basePath is taken from the current request's
 * base URL when there is one (see resolveBasePath below).
 *
 * window.dreeve.appUrl.basePath is what the SPA router uses to tell "the app
 * root" from "a page below it", and to derive the page name that drives
 * per-page JS (the leaflet chunk behind heatmap/photos/milestones):
 *
 *     currentRoute() {
 *         const fallback = '/dashboard', base = basePath();
 *         return '' === base
 *             ? (location.pathname.replace('/', '') ? location.pathname : fallback)
 *             : (location.pathname.replace(/\/+$/, '') === base ? base + fallback : location.pathname);
 *     }
 *
 * Upstream fills basePath from APP_URL's path, which is right for a subdirectory
 * install but empty under Home Assistant ingress: the base path there is a
 * per-session /api/hassio_ingress/<token> prefix that never appears in APP_URL
 * (which is only a placeholder). With basePath empty, the ingress root
 * /api/hassio_ingress/<token>/ did not compare equal to the base, so the router
 * kept the whole prefix as the route, found no nav link matching it, logged
 * "No router link found for ..." and rendered nothing — which is what the admin
 * panel's "Return to app" link (href="/") landed on. The page name came out as
 * "api-hassio_ingress-<token>-heatmap" for the same reason.
 *
 * The rendered page is cached, so CacheableRenderer is overridden to key cache
 * entries per base path; otherwise one session's ingress token would be served
 * to the next session.
 */
final readonly class IndexPage implements Cacheable
{
    public function __construct(
        private ActivityIdRepository $activityIdRepository,
        private GearRepository $gearRepository,
        private ChallengeRepository $challengeRepository,
        private ActivityBestEffortRepository $activityBestEffortRepository,
        private ImageRepository $imageRepository,
        private AppUrl $appUrl,
        private LocaleSwitcher $localeSwitcher,
        private SettingsRepository $settingsRepository,
        private Environment $twig,
        // Optional so upstream's own tests, which construct this class with the
        // arguments above, keep working.
        private ?RequestStack $requestStack = null,
    ) {
    }

    public function getCacheability(): Cacheability
    {
        return Cacheability::for(
            cacheKey: 'index',
            cacheTags: CacheTags::of(
                RootCacheTag::ACTIVITIES,
                RootCacheTag::ACTIVITY_IMAGES,
                RootCacheTag::CHALLENGES,
                // The top nav bar renders the workout assistant when the AI UI is enabled.
                RootCacheTag::SETTINGS_INTEGRATIONS,
                // The leaflet config every map on the page reads is embedded in window.dreeve.
                RootCacheTag::SETTINGS_MAPS,
            ),
        );
    }

    public function render(): string
    {
        $appearance = $this->settingsRepository->appearance();
        $unitSystem = $appearance->getUnitSystem();

        $general = $this->settingsRepository->general();

        return $this->twig->load('html/index.html.twig')->render([
            'totalActivityCount' => $this->activityIdRepository->count(),
            'completedChallenges' => $this->challengeRepository->count(),
            'totalPhotoCount' => $this->imageRepository->count(),
            'hasGear' => $this->gearRepository->hasGear(),
            'athlete' => $general->getAthlete(),
            'profilePictureUrl' => $general->getProfilePictureUrl(),
            'subTitle' => $general->getAppSubTitle(),
            'hasBestEfforts' => $this->activityBestEffortRepository->hasData(),
            'javascriptWindowConstants' => Json::encode([
                'countries' => Countries::getNames($this->localeSwitcher->getLocale()),
                'appUrl' => [
                    'basePath' => $this->resolveBasePath(),
                ],
                'unitSystem' => [
                    'name' => $unitSystem->value,
                    'paceSymbol' => $unitSystem->paceSymbol(),
                    'distanceSymbol' => $unitSystem->distanceSymbol(),
                    'elevationSymbol' => $unitSystem->elevationSymbol(),
                ],
                'leafletConfig' => $this->settingsRepository->maps()->getLeafletConfig(),
            ]),
        ]);
    }

    /**
     * The reverse-proxy prefix (X-Forwarded-Prefix, mapped from the ingress
     * X-Ingress-Path header by the Caddyfile) when the request carries one, else
     * upstream's APP_URL-derived base path. Returned without surrounding slashes,
     * the shape upstream's JS expects.
     */
    private function resolveBasePath(): string
    {
        $baseUrl = trim($this->requestStack?->getCurrentRequest()?->getBaseUrl() ?? '', '/');
        if ('' !== $baseUrl) {
            return $baseUrl;
        }

        return $this->appUrl->getBasePath() ?? '';
    }
}
