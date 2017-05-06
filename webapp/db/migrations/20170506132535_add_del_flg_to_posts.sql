
-- +goose Up
-- SQL in section 'Up' is executed when this migration is applied
ALTER TABLE `posts` ADD `del_flg` TINYINT(1)  NOT NULL  DEFAULT '0'  AFTER `body`;



-- +goose Down
-- SQL section 'Down' is executed when this migration is rolled back
ALTER TABLE `posts` DROP `del_flg`;

