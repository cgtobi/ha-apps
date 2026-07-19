<?php

declare(strict_types=1);

namespace App\Infrastructure\Http\Gate;

use Symfony\Component\HttpFoundation\RedirectResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Generator\UrlGeneratorInterface;

/*
 * OVERRIDDEN UPSTREAM FILE — resync on every image bump.
 *
 * Same as upstream except handle() compares on the base-relative path. Under a
 * reverse proxy that adds a base path (Home Assistant ingress maps X-Ingress-Path
 * to X-Forwarded-Prefix), the URL generator prefixes $target with the request
 * base URL, but Request::getPathInfo() is always base-relative. Comparing the two
 * directly never matches under ingress, so the gate would redirect to its own
 * target endlessly. We strip the base URL from $target for the comparison only,
 * and still redirect to the fully-prefixed $target.
 */
abstract class ConditionalRedirectGate implements Gate
{
    public function __construct(
        private readonly UrlGeneratorInterface $urlGenerator,
    ) {
    }

    abstract protected function shouldGuard(): bool;

    /**
     * @return list<string>
     */
    abstract protected function allowedPaths(): array;

    abstract protected function redirectToRouteName(): string;

    final public function handle(Request $request): GateDecision
    {
        if (!$this->shouldGuard()) {
            return GateDecision::defer();
        }

        $target = $this->urlGenerator->generate($this->redirectToRouteName());

        $targetPath = $target;
        $baseUrl = $request->getBaseUrl();
        if ('' !== $baseUrl && str_starts_with($targetPath, $baseUrl)) {
            $targetPath = substr($targetPath, strlen($baseUrl));
        }
        if ('' === $targetPath) {
            $targetPath = '/';
        }

        $path = $request->getPathInfo();
        foreach ([...$this->allowedPaths(), $targetPath] as $allowed) {
            if ($this->matches($path, $allowed)) {
                return GateDecision::allow();
            }
        }

        return GateDecision::respond(new RedirectResponse($target, Response::HTTP_FOUND));
    }

    private function matches(string $path, string $allowed): bool
    {
        return $path === $allowed
            || str_starts_with($path, rtrim($allowed, '/').'/');
    }
}
