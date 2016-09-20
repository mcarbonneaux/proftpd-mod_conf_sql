CREATE DATABASE proftpd IF NOT EXISTS;
USE DATABASE proftpd;

CREATE TABLE ftpctx IF NOT EXISTS (
  id INTEGER UNSIGNED UNIQUE PRIMARY KEY NOT NULL AUTO_INCREMENT,
  parent_id INTEGER UNSIGNED,
  name VARCHAR(255),
  type VARCHAR(255),
  value VARCHAR(255)
);

CREATE TABLE ftpconf IF NOT EXISTS (
  id INTEGER UNSIGNED UNIQUE PRIMARY KEY NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  value BLOB
);

CREATE TABLE ftpmap IF NOT EXISTS (
  conf_id INTEGER UNSIGNED NOT NULL,
  ctx_id INTEGER UNSIGNED NOT NULL
);
