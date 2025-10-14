# Puma configuration
port ENV.fetch('PORT', 8080)
threads 2, 5
preload_app!
