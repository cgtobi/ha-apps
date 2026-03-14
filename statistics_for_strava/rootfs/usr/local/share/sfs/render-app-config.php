<?php

declare(strict_types=1);

require '/var/www/vendor/autoload.php';

use Symfony\Component\Yaml\Yaml;

if ($argc < 3) {
    fwrite(STDERR, "Usage: render-app-config.php <options.json> <output.yaml>\n");
    exit(1);
}

$optionsFile = $argv[1];
$outputFile = $argv[2];

if (!is_file($optionsFile)) {
    fwrite(STDERR, sprintf("Options file not found: %s\n", $optionsFile));
    exit(1);
}

try {
    $options = json_decode((string) file_get_contents($optionsFile), true, 512, JSON_THROW_ON_ERROR);
} catch (\Throwable $e) {
    fwrite(STDERR, sprintf("Invalid options JSON: %s\n", $e->getMessage()));
    exit(1);
}

if (!is_array($options)) {
    fwrite(STDERR, "Options root must be a JSON object\n");
    exit(1);
}

$appConfigYaml = (string) ($options['app_config_yaml'] ?? '');
if (trim($appConfigYaml) === '') {
    fwrite(STDERR, "Missing app_config_yaml in options\n");
    exit(1);
}

try {
    $config = Yaml::parse($appConfigYaml);
} catch (\Throwable $e) {
    fwrite(STDERR, sprintf("Invalid app_config_yaml: %s\n", $e->getMessage()));
    exit(1);
}

if (!is_array($config)) {
    fwrite(STDERR, "app_config_yaml root must be a YAML mapping/object\n");
    exit(1);
}

$generalAppUrl = trim((string) ($options['general_app_url'] ?? ''));
if ($generalAppUrl !== '') {
    if (false === filter_var($generalAppUrl, FILTER_VALIDATE_URL)) {
        fwrite(STDERR, sprintf("Invalid general_app_url: %s\n", $generalAppUrl));
        exit(1);
    }
    if (!isset($config['general']) || !is_array($config['general'])) {
        $config['general'] = [];
    }
    $config['general']['appUrl'] = $generalAppUrl;
}

$generalAppSubtitle = trim((string) ($options['general_app_subtitle'] ?? ''));
if ($generalAppSubtitle !== '') {
    if (!isset($config['general']) || !is_array($config['general'])) {
        $config['general'] = [];
    }
    $config['general']['appSubTitle'] = $generalAppSubtitle;
}

$generalProfilePictureUrl = trim((string) ($options['general_profile_picture_url'] ?? ''));
if ($generalProfilePictureUrl !== '') {
    if (!isset($config['general']) || !is_array($config['general'])) {
        $config['general'] = [];
    }
    $config['general']['profilePictureUrl'] = $generalProfilePictureUrl;
}

$appearanceLocale = trim((string) ($options['appearance_locale'] ?? ''));
if ($appearanceLocale !== '') {
    $allowedLocales = ['en_US', 'fr_FR', 'it_IT', 'nl_BE', 'de_DE', 'pt_BR', 'pt_PT', 'sv_SE', 'zh_CN'];
    if (!in_array($appearanceLocale, $allowedLocales, true)) {
        fwrite(STDERR, sprintf("Invalid appearance_locale: %s\n", $appearanceLocale));
        exit(1);
    }
    if (!isset($config['appearance']) || !is_array($config['appearance'])) {
        $config['appearance'] = [];
    }
    $config['appearance']['locale'] = $appearanceLocale;
}

$appearanceUnitSystem = trim((string) ($options['appearance_unit_system'] ?? ''));
if ($appearanceUnitSystem !== '') {
    if (!in_array($appearanceUnitSystem, ['metric', 'imperial'], true)) {
        fwrite(STDERR, sprintf("Invalid appearance_unit_system: %s\n", $appearanceUnitSystem));
        exit(1);
    }
    if (!isset($config['appearance']) || !is_array($config['appearance'])) {
        $config['appearance'] = [];
    }
    $config['appearance']['unitSystem'] = $appearanceUnitSystem;
}

$appearanceTimeFormat = (int) ($options['appearance_time_format'] ?? 0);
if ($appearanceTimeFormat !== 0) {
    if (!in_array($appearanceTimeFormat, [12, 24], true)) {
        fwrite(STDERR, sprintf("Invalid appearance_time_format: %d\n", $appearanceTimeFormat));
        exit(1);
    }
    if (!isset($config['appearance']) || !is_array($config['appearance'])) {
        $config['appearance'] = [];
    }
    $config['appearance']['timeFormat'] = $appearanceTimeFormat;
}

$importNumberOfNewActivities = (int) ($options['import_number_of_new_activities_to_process_per_import'] ?? 0);
if ($importNumberOfNewActivities > 0) {
    if (!isset($config['import']) || !is_array($config['import'])) {
        $config['import'] = [];
    }
    $config['import']['numberOfNewActivitiesToProcessPerImport'] = $importNumberOfNewActivities;
}

$importOptInConfigured = (bool) ($options['import_opt_in_to_segment_detail_import_configured'] ?? false);
if ($importOptInConfigured) {
    if (!isset($config['import']) || !is_array($config['import'])) {
        $config['import'] = [];
    }
    $config['import']['optInToSegmentDetailImport'] = (bool) ($options['import_opt_in_to_segment_detail_import'] ?? false);
}

$cronExpression = trim((string) ($options['cron_import_expression'] ?? ''));
if ($cronExpression !== '') {
    if (!isValidCronExpression($cronExpression)) {
        fwrite(STDERR, sprintf("Invalid cron_import_expression: %s\n", $cronExpression));
        exit(1);
    }

    $enabled = (bool) ($options['cron_import_enabled'] ?? false);

    if (!isset($config['daemon']) || !is_array($config['daemon'])) {
        $config['daemon'] = [];
    }

    $cron = $config['daemon']['cron'] ?? [];
    if (!is_array($cron)) {
        $cron = [];
    }

    $updated = false;
    foreach ($cron as $idx => $entry) {
        if (!is_array($entry)) {
            continue;
        }
        if (($entry['action'] ?? null) !== 'importDataAndBuildApp') {
            continue;
        }
        $cron[$idx] = [
            'action' => 'importDataAndBuildApp',
            'expression' => $cronExpression,
            'enabled' => $enabled,
        ];
        $updated = true;
    }

    if (!$updated) {
        $cron[] = [
            'action' => 'importDataAndBuildApp',
            'expression' => $cronExpression,
            'enabled' => $enabled,
        ];
    }

    $config['daemon']['cron'] = $cron;
}

$yaml = Yaml::dump($config, 8, 2);
if (false === file_put_contents($outputFile, $yaml)) {
    fwrite(STDERR, sprintf("Failed to write output YAML: %s\n", $outputFile));
    exit(1);
}

exit(0);

function isValidCronExpression(string $expression): bool
{
    $parts = preg_split('/\s+/', trim($expression));
    if (!is_array($parts) || count($parts) !== 5) {
        return false;
    }

    foreach ($parts as $part) {
        if ($part === '') {
            return false;
        }
    }

    return true;
}
