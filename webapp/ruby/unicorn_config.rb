worker_processes 4
preload_app true
# listen "127.0.0.1:9292"
listen "/tmp/unicorn.sock"
pid "/tmp/unicorn.pid"
# stderr_path "/tmp/unicorn_error.log"
# stdout_path "/tmp/unicorn.log"
