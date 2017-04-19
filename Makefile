.DEFAULT_GOAL := help

start: ## Run Server
	@sudo systemctl start isu-ruby

stop: ## Stop Server
	@sudo systemctl stop isu-ruby

log: ## log Server
	@sudo journalctl -u isu-ruby

restart: ## Restart Server
	@cd webapp/ruby; bundle 1> /dev/null; sudo systemctl restart isu-ruby

nginx-restart: ## Restart nginx
	@sudo service nginx restart

nginx-reset-log: ## reest log and restart nginx
	@sudo rm /var/log/nginx/access.log;sudo service nginx restart

nginx-log: ## tail nginx access.log
	@sudo tail -f /var/log/nginx/access.log

nginx-error-log: ## tail nginx error.log
	@sudo tail -f /var/log/nginx/error.log

myprofiler: ## Run myprofiler
	@myprofiler -user=root

db-slow-query: ## tail slow query log
	@sudo tail -f /var/log/mysql/mysql-slow.log


.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
