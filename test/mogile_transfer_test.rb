require 'test/unit'

require 'rubygems'
require 'activerecord'
require 'openssl'

#set rails env CONSTANT (we are not actually loading rails in this test, but activerecord depends on this constant)
RAILS_ENV = 'test' unless defined?(RAILS_ENV)
CHUNK_SIZE = 4096 unless defined?(CHUNK_SIZE)

MAX_READ_SIZE_FOR_MOGILE_TEST = 65536

class MogileTransferTest < Test::Unit::TestCase
  
  @@is_setup = false
  
  def setup_for_all
    unless @@is_setup
      #setup active record to use a sqlite database
      ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")

      #load the database schema for this test
      load File.expand_path(File.dirname(__FILE__) + "/initech_dms/schema.rb")
      
      #require this plugin
      require "#{File.dirname(__FILE__)}/../init"

      #require the mock models for the voting system
      require File.expand_path(File.dirname(__FILE__) + '/initech_dms/models.rb')
      FileStorage.class_eval do
        def self.backend
          @@mogile_backend ||= FileStorage::Backend::MogileFSStorage.new({
                  :hosts                     => ["127.0.0.1:#{MockMogile.running_mock.tracker_port}"],
                  :domain                    => "cm4_test",
                  :file_class                => "cm4_file",
                  :file_class_devcount       => 3,
                  :chunk_class               => "cm4_chunk",
                  :chunk_class_devcount      => 2
                }
          )
        end
        def self.max_read_size
          MAX_READ_SIZE_FOR_MOGILE_TEST
        end
      end
      @@is_setup = true
    end
  end
  
  def setup
    unless defined?(MockMogile)
      #load mogile mocks
      load File.expand_path(File.dirname(__FILE__) + "/mogile_mocks.rb")
    end
    MockMogile.reset
    setup_for_all
  end
  
  def test_retrieve_file_url
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }        
    tps_report = TpsReport.new
    tps_report.data = data_to_store
    tps_report.save!
    
    tps_report = TpsReport.find(tps_report.id)

    file_url = tps_report.managed_document.get_forwardable_url
    size = tps_report.managed_document.size
    
    new_report = TpsReport.new
    new_report.save!
    new_report.copy_data_from_url(file_url, size)
    
    tps_report = TpsReport.find(tps_report.id)
    new_report = TpsReport.find(new_report.id)
    
    assert_equal(tps_report.data, new_report.data)
  end
  
  def test_copy_file
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }        
    tps_report = TpsReport.new
    tps_report.data = data_to_store
    tps_report.save!
    
    tps_report = TpsReport.find(tps_report.id)
  
    new_report = TpsReport.new
    new_report.save!
    new_report.copy_data_from(tps_report)
    
    tps_report = TpsReport.find(tps_report.id)
    new_report = TpsReport.find(new_report.id)
    
    assert_equal(tps_report.data, new_report.data)    
  end

end
