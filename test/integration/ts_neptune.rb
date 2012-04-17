STORAGE_TYPES = ["appdb", "gstorage", "s3", "walrus"] - ["appdb"]

$:.unshift File.join(File.dirname(__FILE__), "..", "..", "lib")
require 'neptune'

$:.unshift File.join(File.dirname(__FILE__), "..", "test", "integration")
require 'test_helper'

REQUIRED_CREDS = %w{ APPSCALE_HEAD_NODE
GSTORAGE_ACCESS_KEY GSTORAGE_SECRET_KEY GSTORAGE_URL 
S3_ACCESS_KEY S3_SECRET_KEY S3_URL 
WALRUS_ACCESS_KEY WALRUS_SECRET_KEY WALRUS_URL }

require 'test/unit'
require 'rubygems'
require 'flexmock/test_unit'

REQUIRED_CREDS.each { |cred|
  msg = "The environment variable #{cred} was not set. Please " +
    "set it and try again."
  abort(msg) if ENV[cred].nil?
}

APPSCALE_HEAD_NODE_IP = ENV['APPSCALE_HEAD_NODE']
msg = "AppScale is not currently running at " +
  "#{APPSCALE_HEAD_NODE_IP}. Please start AppScale and try again."
abort(msg) unless TestHelper.is_appscale_running?(APPSCALE_HEAD_NODE_IP)

# TODO: refactor dfsp and dwssa to use the new ssa job type

require 'tc_c'
#require 'tc_dfsp'
#require 'tc_dwssa'
require 'tc_erlang'
require 'tc_mapreduce'
require 'tc_mpi'
require 'tc_storage'
require 'tc_upc'
require 'tc_x10'

