<?php
$databases['default']['default'] = array (
  'database' => getenv('DRUPAL_DATABASE_NAME'),
  'username' => getenv('DRUPAL_DATABASE_USERNAME'),
  'password' => getenv('DRUPAL_DATABASE_PASSWORD'),
  'prefix' => '',
  'host' => getenv('DRUPAL_DATABASE_HOST'),
  'port' => getenv('DRUPAL_DATABASE_PORT'),
  'namespace' => 'Drupal\\Core\\Database\\Driver\\mysql',
  'driver' => 'mysql',
);
$settings['hash_salt'] = getenv('DRUPAL_HASH_SALT') ?: 'NlCzRMsf0egmrHNqN1RQfYZ6j94qLhFjZ7iVDcs';
$settings['trusted_host_patterns'] = ['.*'];
$settings['config_sync_directory'] = 'sites/default/files/config_sync';
$settings['file_private_path'] = 'sites/default/files/private';