# Programmer: Chris Bunch (cgb@cs.ucsb.edu)

$:.unshift File.join(File.dirname(__FILE__), "..", "..", "lib")
require 'common_functions'

require 'test/unit'

SECRET = "hey-its-a-secret"


class TestCommonFunctions < Test::Unit::TestCase
  def setup
    @commonfunctions = flexmock(CommonFunctions)
    @commonfunctions.should_receive(:scp_file).and_return()
    @commonfunctions.should_receive(:shell).and_return()

    @file = flexmock(File)
    @file.should_receive(:expand_path).and_return("")

    @fileutils = flexmock(FileUtils)
    @fileutils.should_receive(:rm_f).and_return()

    @yaml = flexmock(YAML)

    @yaml_info = { :secret => SECRET, :shadow => SECRET }
  end

  def test_scp_to_shadow
    @file.should_receive(:exists?).and_return(true)
    @yaml.should_receive(:load_file).and_return(@yaml_info)

    assert_nothing_raised(Exception) {
      CommonFunctions.scp_to_shadow("", "", "", "")
    }
  end

  def test_get_secret_key_file_exists
    @file.should_receive(:exists?).and_return(true)
    @yaml.should_receive(:load_file).and_return(@yaml_info)

    assert_equal(SECRET, CommonFunctions.get_secret_key("", required=true))
  end

  def test_get_secret_key_malformed_yaml
    assert_raise(BadConfigurationException) {
      CommonFunctions.get_secret_key("", required=true)
    }
  end

  def test_get_secret_key_wrong_tag
    assert_raise(BadConfigurationException) {
      CommonFunctions.get_secret_key("", required=true)
    }

    @file.should_receive(:exists?).and_return(true)

    yaml_info_no_secret = { :shadow => SECRET }
    @yaml.should_receive(:load_file).and_return(yaml_info_no_secret)

    assert_nil(CommonFunctions.get_secret_key("", required=false))
  end

  def test_get_secret_key_file_doesnt_exist
    @file.should_receive(:exists).and_return(false)
    
    assert_raise(BadConfigurationException) {
      CommonFunctions.get_secret_key("", required=true)
    }
  end
end
