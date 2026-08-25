<?php

declare(strict_types=1);

/*
 * Validate and normalize the add-on's admin_allowed_ips option.
 *
 * Upstream parses ADMIN_ALLOWED_IPS into a value object that throws on a malformed
 * entry — but it does so while handling a request, not at boot. The add-on would
 * start, /healthz would stay green, the watchdog would be happy, and /admin alone
 * would answer 400 with nothing in the log to explain it. So the value is checked
 * here first, with the same rules upstream applies (IP or CIDR, comma-separated),
 * and start.sh refuses to export a value that would not parse.
 *
 * The Home Assistant supervisor network is always added. Upstream's gate runs on
 * every request, ingress included, so an allowlist without it can lock the user out
 * of the admin panel in the HA sidebar — the way most people reach it. Ingress
 * already requires a Home Assistant login, so nothing is given away by keeping it
 * reachable; the allowlist is there for the optional 8080/tcp port.
 *
 * Prints the normalized list on success. On a bad entry, prints the reason and
 * exits non-zero.
 */

const SUPERVISOR_NETWORK = '172.30.32.0/23';

function isValidIpOrCidr(string $entry): bool
{
    if (!str_contains($entry, '/')) {
        return false !== filter_var($entry, FILTER_VALIDATE_IP);
    }

    [$address, $prefix] = explode('/', $entry, 2);

    if (false === filter_var($address, FILTER_VALIDATE_IP)) {
        return false;
    }

    if ('' === $prefix || !ctype_digit($prefix)) {
        return false;
    }

    $max = false !== filter_var($address, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) ? 32 : 128;

    return (int) $prefix <= $max;
}

$raw = $argv[1] ?? '';
$entries = array_values(array_filter(array_map('trim', explode(',', $raw)), static fn (string $e): bool => '' !== $e));

foreach ($entries as $entry) {
    if (!isValidIpOrCidr($entry)) {
        fwrite(STDOUT, sprintf('"%s" is not a valid IP address or CIDR range', $entry));
        exit(1);
    }
}

if ([] === $entries) {
    fwrite(STDOUT, 'the list is empty');
    exit(1);
}

if (!in_array(SUPERVISOR_NETWORK, $entries, true)) {
    array_unshift($entries, SUPERVISOR_NETWORK);
}

fwrite(STDOUT, implode(',', $entries));
