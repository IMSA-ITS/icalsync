source 'https://rubygems.org'

if RUBY_VERSION.delete('.').to_i < 192
  puts('Ruby should be >1.9.2')
  exit 1
end

gem 'awesome_print'
gem 'dotenv'
gem 'google-api-client', '~> 0.9.0'
gem 'googleauth'
gem 'icalendar'
gem 'mime-types', '< 3'
gem 'pry'
# gem 'signet', '~> 0.6'
gem 'json', '~> 1.8'

group :test do
  gem 'test-unit'
end
