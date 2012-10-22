USE nova_bm;

TRUNCATE bm_nodes;
TRUNCATE bm_interfaces;

USE nova;

CREATE TABLE IF NOT EXISTS user_quotas (id INT(11) NOT NULL AUTO_INCREMENT, created_at datetime DEFAULT NULL, updated_at DATETIME DEFAULT NULL, deleted_at DATETIME DEFAULT NULL, deleted TINYINT(1) DEFAULT NULL, user_id VARCHAR(255) DEFAULT NULL, project_id VARCHAR(255) DEFAULT NULL, resource VARCHAR(255) NOT NULL, hard_limit INT(11) DEFAULT NULL, PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
ALTER TABLE reservations add COLUMN user_id varchar(255) DEFAULT NULL;
ALTER TABLE quota_usages add COLUMN user_id varchar(255) DEFAULT NULL;
