#!/usr/bin/env puma

workers Integer(ENV['WEB_CONCURRENCY'] || 4)
threads_count = Integer(ENV['MAX_THREADS'] || 5)
threads threads_count, threads_count

bind 'tcp://0.0.0.0:8080'
# bind 'unix:///var/run/puma.sock'
# port        ENV['PORT']     || 8080
environment ENV['RACK_ENV'] || 'development'

stdout_redirect 'tmp/puma.log', 'tmp/puma.error', true

preload_app!
