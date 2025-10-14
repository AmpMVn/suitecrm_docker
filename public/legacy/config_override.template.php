<?php
// Helper pro čtení s fallbackem: SUITECRM_* → neprefixované → default
$env = function (string $suitecrmKey, string $plainKey = null, $default = null) {
    $v = getenv($suitecrmKey);
    if ($v !== false && $v !== '') return $v;
    if ($plainKey) {
        $v = getenv($plainKey);
        if ($v !== false && $v !== '') return $v;
    }
    return $default;
};

// --- Database (fallback na 'db' + port 3306) ---
$sugar_config['dbconfig']['db_host_name'] = $env('SUITECRM_DB_HOST', 'DB_HOST', 'db');
$sugar_config['dbconfig']['db_user_name'] = $env('SUITECRM_DB_USER', 'DB_USER', 'suitecrm');
$sugar_config['dbconfig']['db_password']  = $env('SUITECRM_DB_PASSWORD', 'DB_PASSWORD', 'secret');
$sugar_config['dbconfig']['db_name']      = $env('SUITECRM_DB_NAME', 'DB_NAME', 'suitecrm');
$sugar_config['dbconfig']['db_type']      = 'mysqli';
$sugar_config['dbconfig']['db_manager']   = 'MysqliManager';
$sugar_config['dbconfig']['db_port']      = (int) $env('SUITECRM_DB_PORT', 'DB_PORT', 3306);

// --- Redis session handler ---
$sugar_config['session']['sessionHandler'] = 'redis';
$sugar_config['session']['redis']['host']  = $env('SUITECRM_REDIS_HOST', 'REDIS_HOST', 'redis');
$sugar_config['session']['redis']['port']  = (int) $env('SUITECRM_REDIS_PORT', 'REDIS_PORT', 6379);

// --- Mail (Mailhog) ---
$sugar_config['smtp']['host'] = $env('SUITECRM_SMTP_HOST', 'SMTP_HOST', 'mailhog');
$sugar_config['smtp']['port'] = (int) $env('SUITECRM_SMTP_PORT', 'SMTP_PORT', 1025);

// --- Search (Elasticsearch) ---
$sugar_config['search']['engine'] = 'Elastic';
$sugar_config['search']['elasticsearch']['host']   = $env('SUITECRM_ELASTIC_HOST', 'ELASTIC_HOST', 'elasticsearch');
$sugar_config['search']['elasticsearch']['port']   = (int) $env('SUITECRM_ELASTIC_PORT', 'ELASTIC_PORT', 9200);
$sugar_config['search']['elasticsearch']['scheme'] = 'http';
$sugar_config['search']['enabled'] = true;

// --- Logging ---
$sugar_config['logger']['level'] = 'fatal';

// --- Site URL (nepovinné) ---
$sugar_config['site_url'] = sprintf('http://localhost:%s', $env('SUITECRM_APP_PORT', null, 8080));

// --- Misc ---
$sugar_config['cache_dir']  = 'cache/';
$sugar_config['upload_dir'] = 'upload/';
$sugar_config['log_dir']    = 'log/';
