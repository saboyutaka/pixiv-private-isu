
-- +goose Up
-- SQL in section 'Up' is executed when this migration is applied
ALTER TABLE `posts` ADD INDEX (`del_flg`);
ALTER TABLE `posts` ADD INDEX (`created_at`);


-- +goose Down
-- SQL section 'Down' is executed when this migration is rolled back
ALTER TABLE `posts` DROP INDEX `del_flg`;
ALTER TABLE `posts` DROP INDEX `created_at`;
