<?php

declare(strict_types=1);

namespace App\Application;

use App\Application\Navigation\NavigationSection;
use App\Application\Navigation\SideBar;
use App\Application\OpenGraph\OpenGraph;
use App\Domain\Settings\SettingsRepository;
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
 * window.dreeve.appUrl.basePath is what the JS prepends to the URLs it builds
 * itself: the AI assistant's /chat/sse stream and /chat/clear, and the chart
 * click-throughs to /monthly-stats/<month> and /activities?<filters>.
 *
 * Upstream fills basePath from APP_URL's path, which is right for a subdirectory
 * install but empty under Home Assistant ingress: the base path there is a
 * per-session /api/hassio_ingress/<token> prefix that never appears in APP_URL
 * (which is only a placeholder). With basePath empty those URLs resolve against
 * the Home Assistant host root instead of the ingress session.
 *
 * Upstream does not cache the shell (PageRenderer caches only the page content
 * it wraps, and SideBar its own fragment), so the per-request value needs no
 * cache keying of its own.
 */
final readonly class AppShell
{
    public function __construct(
        private SideBar $sideBar,
        private AppUrl $appUrl,
        private LocaleSwitcher $localeSwitcher,
        private SettingsRepository $settingsRepository,
        private Environment $twig,
        // Optional so upstream's own tests, which construct this class with the
        // arguments above, keep working.
        private ?RequestStack $requestStack = null,
    ) {
    }

    public function render(string $content, ?NavigationSection $navigationSection, ?OpenGraph $openGraph): string
    {
        $appearance = $this->settingsRepository->appearance();
        $unitSystem = $appearance->getUnitSystem();

        $general = $this->settingsRepository->general();

        return $this->twig->load('html/app-shell.html.twig')->render([
            'content' => $content,
            'openGraph' => $openGraph,
            'sidebar' => $this->sideBar->render($navigationSection),
            'athlete' => $general->getAthlete(),
            'profilePictureUrl' => $general->getProfilePictureUrl(),
            'subTitle' => $general->getAppSubTitle(),
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
