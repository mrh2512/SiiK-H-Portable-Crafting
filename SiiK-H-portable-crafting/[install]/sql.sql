-- XP/Level table
CREATE TABLE IF NOT EXISTS `siik_portablecrafting_xp` (
  `citizenid` VARCHAR(64) NOT NULL,
  `xp` INT NOT NULL DEFAULT 0,
  `level` INT NOT NULL DEFAULT 1,
  `crafts` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Persistent placed crafting tables
CREATE TABLE IF NOT EXISTS `siik_portablecrafting_tables` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `owner_citizenid` VARCHAR(64) NOT NULL,
  `table_type` VARCHAR(32) NOT NULL,
  `x` DOUBLE NOT NULL,
  `y` DOUBLE NOT NULL,
  `z` DOUBLE NOT NULL,
  `h` DOUBLE NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `owner_idx` (`owner_citizenid`),
  KEY `type_idx` (`table_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
