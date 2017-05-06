
-- +goose Up
-- SQL in section 'Up' is executed when this migration is applied
ALTER TABLE `users` ADD INDEX (`del_flg`);
ALTER TABLE `users` ADD INDEX (`authority`);



-- +goose Down
-- SQL section 'Down' is executed when this migration is rolled back
ALTER TABLE `users` DROP INDEX `del_flg`;
ALTER TABLE `users` DROP INDEX `authority`;

