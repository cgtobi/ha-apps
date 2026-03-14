<?php

declare(strict_types=1);

$startupGraceSeconds = 120;

$checks = [
    '/data/config/app/config.yaml' => ['exists' => true, 'readable' => true],
    '/data/storage/database' => ['exists' => true, 'writable' => true],
    '/data/storage/files/logs' => ['exists' => true, 'writable' => true],
    '/data/build/html' => ['exists' => true, 'readable' => true],
];

$errors = false;

foreach ($checks as $path => $expect) {
    if (($expect['exists'] ?? false) && !file_exists($path)) {
        $errors = true;
        continue;
    }
    if (($expect['readable'] ?? false) && !is_readable($path)) {
        $errors = true;
    }
    if (($expect['writable'] ?? false) && !is_writable($path)) {
        $errors = true;
    }
}

$pidFile = '/data/runtime/daemon.pid';
$daemonPid = is_readable($pidFile) ? trim((string) file_get_contents($pidFile)) : '';
$startupMarkerFile = '/data/runtime/health.startup';
$startupAgeSeconds = PHP_INT_MAX;
if (is_file($startupMarkerFile)) {
    $mtime = filemtime($startupMarkerFile);
    if (false !== $mtime) {
        $startupAgeSeconds = time() - $mtime;
    }
}

if ($daemonPid === '' || !ctype_digit($daemonPid)) {
    // Allow short startup grace period to avoid watchdog flapping on boot.
    if ($startupAgeSeconds > $startupGraceSeconds) {
        $errors = true;
    }
} else {
    $procDir = '/proc/'.$daemonPid;
    $cmdlineFile = $procDir.'/cmdline';
    $cmdline = is_readable($cmdlineFile) ? (string) file_get_contents($cmdlineFile) : '';
    if (!is_dir($procDir) || $cmdline === '' || !str_contains($cmdline, 'bin/console')) {
        $errors = true;
    }
}

if ($errors) {
    http_response_code(503);
    header('Content-Type: text/plain; charset=utf-8');
    echo "NOT_OK\n";
    exit;
}

http_response_code(200);
header('Content-Type: text/plain; charset=utf-8');
echo "OK\n";
