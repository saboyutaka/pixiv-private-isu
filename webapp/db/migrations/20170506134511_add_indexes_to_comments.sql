
-- +goose Up
-- SQL in section 'Up' is executed when this migration is applied
ALTER TABLE `comments` ADD INDEX `post_id_created_at` (`post_id`, `created_at`);
ALTER TABLE `comments` ADD INDEX (`user_id`);



-- +goose Down
-- SQL section 'Down' is executed when this migration is rolled back
ALTER TABLE `comments` DROP INDEX `user_id`;
ALTER TABLE `comments` DROP INDEX `post_id_created_at`;

