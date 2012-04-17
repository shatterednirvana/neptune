rm -rf coverage
# By default, we want to test coverage on the unit tests we have
rcov test/unit/ts_all.rb -x /usr/local/lib/site_ruby/1.8/rubygems/gem_path_searcher.rb

# Uncomment me for integration test coverage
# As of Neptune 0.1.1, this is definitely broken
#rcov test/integration/ts_neptune.rb -x /usr/local/lib/site_ruby/1.8/rubygems/gem_path_searcher.rb

