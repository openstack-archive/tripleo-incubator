USE nova;

CREATE TABLE IF NOT EXISTS user_quotas (id INT(11) NOT NULL AUTO_INCREMENT, created_at datetime DEFAULT NULL, updated_at DATETIME DEFAULT NULL, deleted_at DATETIME DEFAULT NULL, deleted TINYINT(1) DEFAULT NULL, user_id VARCHAR(255) DEFAULT NULL, project_id VARCHAR(255) DEFAULT NULL, resource VARCHAR(255) NOT NULL, hard_limit INT(11) DEFAULT NULL, PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DELIMITER //
DROP PROCEDURE IF EXISTS upgrade_database_to_bm //
create procedure upgrade_database_to_bm ()
BEGIN

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = "reservations" AND COLUMN_NAME = "user_id")
THEN
    ALTER TABLE reservations add COLUMN user_id varchar(255) DEFAULT NULL;
END IF;

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = "quota_usages" AND COLUMN_NAME = "user_id")
THEN
    ALTER TABLE quota_usages add COLUMN user_id varchar(255) DEFAULT NULL;
END IF;

END //

CALL upgrade_database_to_bm //
DELIMITER ;
drop procedure if exists upgrade_database_to_bm;
