# frozen_string_literal: true

source "https://rubygems.org"

ruby "3.4.10"

# Needs 1.29.4 for Work.create(handle:). An older gem drops the handle,
# and /complete then mints a second one.
gem "atlas_rb", "~> 1.29", ">= 1.29.4"
gem "dotenv", "~> 3.1"
gem "rexml", "~> 3.4"

group :test do
  gem "rspec", "~> 3.13"
  gem "webmock", "~> 3.24"
end
