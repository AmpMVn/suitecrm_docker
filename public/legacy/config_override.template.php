<?php
/**
 * Dynamický config_override.php
 * - čte proměnné z .env / Docker env
 * - podporuje více paralelních instancí (SUITECRM_PROJECT_NAME)
 * - automaticky odvodí site_url z SUITECRM_WEB_HOST + SUITECRM_WEB_PORT_HOST nebo SITE_URL
 */

$env = static function (string $suitecrmKey, ?string $plainKey = null, $default = null) {
    $v = getenv($suitecrmKey);
    if ($v !== false && $v !== '') return $v;
    if ($plainKey) {
        $v = getenv($plainKey);
        if ($v !== false && $v !== '') return $v;
    }
    return $default;
};

// --- Database ---
$sugar_config['dbconfig'] = [
    'db_host_name' => $env('SUITECRM_DB_HOST', 'DB_HOST', 'db'),
    'db_user_name' => $env('SUITECRM_DB_USER', 'DB_USER', 'suitecrm'),
    'db_password'  => $env('SUITECRM_DB_PASSWORD', 'DB_PASSWORD', 'secret'),
    'db_name'      => $env('SUITECRM_DB_NAME', 'DB_NAME', 'suitecrm'),
    'db_type'      => 'mysqli',
    'db_manager'   => 'MysqliManager',
    'db_port'      => (int) $env('SUITECRM_DB_PORT', 'DB_PORT', 3306),
];

// --- Redis (session handler) ---
$sugar_config['session']['sessionHandler'] = 'redis';
$sugar_config['session']['redis'] = [
    'host' => $env('SUITECRM_REDIS_HOST', 'REDIS_HOST', 'redis'),
    'port' => (int) $env('SUITECRM_REDIS_PORT', 'REDIS_PORT', 6379),
];

// --- Mail (Mailhog) ---
$sugar_config['smtp'] = [
    'host' => $env('SUITECRM_SMTP_HOST', 'SMTP_HOST', 'mailhog'),
    'port' => (int) $env('SUITECRM_SMTP_PORT', 'SMTP_PORT', 1025),
];

// --- Elasticsearch ---
$sugar_config['search'] = [
    'engine' => 'Elastic',
    'elasticsearch' => [
        'host'   => $env('SUITECRM_ELASTIC_HOST', 'ELASTIC_HOST', 'elasticsearch'),
        'port'   => (int) $env('SUITECRM_ELASTIC_PORT', 'ELASTIC_PORT', 9200),
        'scheme' => 'http',
    ],
    'enabled' => true,
];

// --- Logging ---
$sugar_config['logger']['level'] = $env('MAIN_LOG_LEVEL', 'LOGGER_LEVEL', 'fatal');

// --- Site URL ---
$siteUrl = $env('SITE_URL');
if (!$siteUrl) {
    $host = $env('SUITECRM_WEB_HOST', null, 'localhost');
    $port = $env('SUITECRM_WEB_PORT_HOST', 'SUITECRM_APP_PORT', 8080);
    $scheme = $env('APP_SCHEME', null, 'http');
    $siteUrl = sprintf('%s://%s:%s', $scheme, $host, $port);
}
$sugar_config['site_url'] = rtrim($siteUrl, '/');

// --- Misc ---
$sugar_config['cache_dir']  = 'cache/';
$sugar_config['upload_dir'] = 'upload/';
$sugar_config['log_dir']    = 'logs/'; // sjednoceno s tvojí strukturou

// --- Optional diagnostics ---
if (getenv('APP_DEBUG')) {
    $sugar_config['logger']['level'] = 'debug';
}
