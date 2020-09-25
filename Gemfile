# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in bright_serializer.gemspec
gemspec

gem 'oj', require: false

group :test do
  gem 'faker'
  gem 'rubocop'
  gem 'rubocop-performance'
  gem 'rubocop-rspec'
  gem 'simplecov'
  gem 'delta-simplecov-checks', git: 'https://github.com/Bhacaz/delta-simplecov-checks'
end
