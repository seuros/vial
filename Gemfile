# frozen_string_literal: true

source "https://rubygems.org"

gemspec

if ENV["RAILS_VERSION"] == "edge"
  gem "activerecord", github: "rails/rails", branch: "main"
  gem "activesupport", github: "rails/rails", branch: "main"
end

group :development, :test do
  gem "benchmark"
  gem "benchmark-ips"
end
