CREATE TABLE IF NOT EXISTS `coii_multicharacter_slots` (
    `identifier` VARCHAR(64) NOT NULL,
    `purchased_slots` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `coii_multicharacter_preferences` (
    `identifier` VARCHAR(64) NOT NULL,
    `settings` LONGTEXT NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `users`
    ADD COLUMN IF NOT EXISTS `last_played` DATETIME NULL DEFAULT NULL;

ALTER TABLE `users`
    ADD COLUMN IF NOT EXISTS `disabled` TINYINT(1) NOT NULL DEFAULT 0;

-- Optional one-time migration when replacing stock esx_multicharacter and using
-- two free slots with a maximum of one paid slot. Config.AutoMigrate performs
-- this automatically when the new ownership table is first created.
-- INSERT INTO `coii_multicharacter_slots` (`identifier`, `purchased_slots`)
-- SELECT `identifier`, LEAST(1, GREATEST(`slots` - 2, 0))
-- FROM `multicharacter_slots` WHERE `slots` > 2
-- ON DUPLICATE KEY UPDATE `purchased_slots` = GREATEST(`purchased_slots`, VALUES(`purchased_slots`));
