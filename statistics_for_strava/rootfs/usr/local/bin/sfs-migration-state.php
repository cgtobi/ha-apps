<?php

declare(strict_types=1);

/*
 * Reports where the persisted database sits relative to the upstream migration
 * squash, without booting Symfony (the container may not even be buildable at
 * this point, and this has to run before the first console command).
 *
 * Mirrors App\Infrastructure\Doctrine\Migrations\MigrationSquashHandler, whose
 * two constants are extracted from the image at build time — see
 * sfs-prepare-migration-guard.sh. Upstream throws MigrationsOutdated when the
 * database is at neither the squashed migration nor the last one before it;
 * this tells the add-on that ahead of time, and whether the gap is one we can
 * close ourselves from the stashed pre-squash migrations.
 *
 * Usage: sfs-migration-state.php <squashId> <lastBeforeSquashId> <stashDir> [dbPath]
 * Prints exactly one of: fresh | ok | remediable | blocked | unknown
 */

$squashId = $argv[1] ?? '';
$lastId = $argv[2] ?? '';
$stashDir = $argv[3] ?? '';
$dbPath = $argv[4] ?? '/data/storage/database/dreeve.db';

function bail(string $reason): never
{
    fwrite(STDERR, $reason."\n");
    echo "unknown\n";
    exit(0);
}

if ('' === $squashId || '' === $lastId) {
    bail('sfs-migration-state: squash ids missing');
}

if (!file_exists($dbPath) || 0 === filesize($dbPath)) {
    echo "fresh\n";
    exit(0);
}

try {
    $pdo = new PDO('sqlite:'.$dbPath, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

    $table = $pdo->query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'migration_versions'")->fetchColumn();
    if (false === $table) {
        // No migration bookkeeping yet: upstream treats this as a fresh install
        // and lets the squashed migration create the schema.
        echo "fresh\n";
        exit(0);
    }

    // Compare on the bare VersionYYYYMMDDHHMMSS part. The rows carry the fully
    // qualified class name, and the namespace is upstream's to change.
    $executed = [];
    foreach ($pdo->query('SELECT version FROM migration_versions')->fetchAll(PDO::FETCH_COLUMN) as $version) {
        $pos = strrpos((string) $version, '\\');
        $executed[] = false === $pos ? (string) $version : substr((string) $version, $pos + 1);
    }
} catch (Throwable $e) {
    bail('sfs-migration-state: could not read '.$dbPath.': '.$e->getMessage());
}

if (in_array($squashId, $executed, true) || in_array($lastId, $executed, true)) {
    echo "ok\n";
    exit(0);
}

// The gap is closable only if the stashed pre-squash migrations know where this
// database is — i.e. at least one executed migration is one of theirs. A
// database older than the stash (it predates an earlier squash, or is not ours)
// would make the first stashed migration try to CREATE TABLE over live tables.
$stashed = [];
foreach (glob(rtrim($stashDir, '/').'/Version*.php') ?: [] as $file) {
    $stashed[] = basename($file, '.php');
}

echo [] !== array_intersect($executed, $stashed) ? "remediable\n" : "blocked\n";
