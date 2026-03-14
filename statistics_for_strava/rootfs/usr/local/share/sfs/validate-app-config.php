<?php

declare(strict_types=1);

require '/var/www/vendor/autoload.php';

use Symfony\Component\Yaml\Yaml;

if ($argc < 2) {
    fwrite(STDERR, "Missing config file argument\n");
    exit(1);
}

$configFile = $argv[1];

if (!is_file($configFile)) {
    fwrite(STDERR, sprintf("Config file not found: %s\n", $configFile));
    exit(1);
}

try {
    $parsed = Yaml::parseFile($configFile);
} catch (\Throwable $e) {
    fwrite(STDERR, sprintf("YAML parse error: %s\n", $e->getMessage()));
    exit(1);
}

if (!is_array($parsed)) {
    fwrite(STDERR, "Config root must be a YAML mapping/object\n");
    exit(1);
}

if (!array_key_exists('general', $parsed) || !is_array($parsed['general'])) {
    fwrite(STDERR, "Missing required config key: general\n");
    exit(1);
}

if (!array_key_exists('appUrl', $parsed['general']) || !is_string($parsed['general']['appUrl']) || trim($parsed['general']['appUrl']) === '') {
    fwrite(STDERR, "Invalid required config value: general.appUrl must be a non-empty string\n");
    exit(1);
}

// Optional compatibility checks for legacy configs.
if (array_key_exists('athlete', $parsed['general']) && !is_array($parsed['general']['athlete'])) {
    fwrite(STDERR, "Invalid config type: general.athlete must be a mapping/object when present\n");
    exit(1);
}

if (isset($parsed['general']['athlete']) && is_array($parsed['general']['athlete'])) {
    $athlete = $parsed['general']['athlete'];

    if (array_key_exists('weightHistory', $athlete) && !is_array($athlete['weightHistory'])) {
        fwrite(STDERR, "Invalid config type: general.athlete.weightHistory must be a mapping/object when present\n");
        exit(1);
    }

    if (array_key_exists('ftpHistory', $athlete)) {
        if (!is_array($athlete['ftpHistory'])) {
            fwrite(STDERR, "Invalid config type: general.athlete.ftpHistory must be a mapping/object when present\n");
            exit(1);
        }
        if (array_key_exists('cycling', $athlete['ftpHistory']) && !is_array($athlete['ftpHistory']['cycling'])) {
            fwrite(STDERR, "Invalid config type: general.athlete.ftpHistory.cycling must be an array when present\n");
            exit(1);
        }
        if (array_key_exists('running', $athlete['ftpHistory']) && !is_array($athlete['ftpHistory']['running'])) {
            fwrite(STDERR, "Invalid config type: general.athlete.ftpHistory.running must be an array when present\n");
            exit(1);
        }
    }
}

if (array_key_exists('zwift', $parsed)) {
    if (!is_array($parsed['zwift'])) {
        fwrite(STDERR, "Invalid config type: zwift must be a mapping/object when present\n");
        exit(1);
    }
    foreach (['level', 'racingScore'] as $key) {
        if (array_key_exists($key, $parsed['zwift']) && !is_scalar($parsed['zwift'][$key]) && null !== $parsed['zwift'][$key]) {
            fwrite(STDERR, sprintf("Invalid config type: zwift.%s must be scalar or null when present\n", $key));
            exit(1);
        }
    }
}

exit(0);
