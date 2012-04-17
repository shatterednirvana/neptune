#!/usr/bin/ruby -w
# Programmer: Chris Bunch

module TestHelper
  def self.compile_code(location, main_file, compiled_location)
    result = neptune(
      :type => "compile",
      :code => location,
      :main => main_file,
      :output => "/baz",
      :copy_to => compiled_location
    )

    puts "standard out is #{result[:out]}"
    puts "standard err is #{result[:err]}"

    return result[:out], result[:err]
  end

  def self.start_job(type, code_location, output, storage, extras={})
    params = {
      :type => type,
      :code => code_location,
      :output => output,
      :nodes_to_use => 1
    }.merge(TestHelper.get_storage_params(storage)).merge(extras)

    status = nil

    loop {
      status = neptune(params)
      if status[:msg] =~ /not enough free nodes/
        puts status[:msg]
      else
        break
      end
      sleep(5)
    }

    return status
  end

  def self.get_job_output(output, storage)
    result = ""

    params = {
      :type => "output",
      :output => output
    }.merge(TestHelper.get_storage_params(storage))

    loop {
      result = neptune(params)

      break if result != "error: output does not exist"
      puts "Waiting for job to complete..."
      sleep(30)
    }

    return result
  end

  def self.get_output_location(file, storage="appdb", notxt=false)
    output = "/neptune"

    if storage == "walrus"
      output << "_"
    else
      output << "-"
    end

    output << "testbin/#{file}"
    if !notxt
      output << ".txt"
    end

    return output
  end

  def self.get_storage_params(storage)
    if storage == "gstorage"
      return {
        :storage => "gstorage",
        :EC2_ACCESS_KEY => ENV['GSTORAGE_ACCESS_KEY'],
        :EC2_SECRET_KEY => ENV['GSTORAGE_SECRET_KEY'],
        :S3_URL => ENV['GSTORAGE_URL']
      }
    elsif storage == "s3"
      return {
        :storage => "s3",
        :EC2_ACCESS_KEY => ENV['S3_ACCESS_KEY'],
        :EC2_SECRET_KEY => ENV['S3_SECRET_KEY'],
        :S3_URL => ENV['S3_URL']
      }
    elsif storage == "walrus"
      return {
        :storage => "s3",
        :EC2_ACCESS_KEY => ENV['WALRUS_ACCESS_KEY'],
        :EC2_SECRET_KEY => ENV['WALRUS_SECRET_KEY'],
        :S3_URL => ENV['WALRUS_URL']
      }
    else
      return { :storage => storage }
      # nothing special to do
    end
  end

  def self.write_file(location, contents)
    File.open(location, "w+") { |file| file.write(contents) }
  end

  def self.read_file(location)
    File.open(location) { |f| f.read.chomp! }
  end

  def self.get_random_alphanumeric(length=10)
    random = ""
    possible = "0123456789abcdefghijklmnopqrstuvxwyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    possibleLength = possible.length

    length.times { |index|
      random << possible[rand(possibleLength)]
    }

    return random
  end

  def self.is_appscale_running?(ip)
    begin
      Net::HTTP.get_response(URI.parse("http://#{ip}"))
      return true
    rescue Exception
      return false
    end
  end
end
