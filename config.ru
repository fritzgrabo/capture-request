require 'dotenv'
Dotenv.load('.env.local', '.env')

require_relative 'app'

run App.new
