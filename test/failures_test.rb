require 'test/unit'

require 'rubygems'
require 'activerecord'

#set rails env CONSTANT (we are not actually loading rails in this test, but activerecord depends on this constant)
RAILS_ENV = 'test' unless defined?(RAILS_ENV)
CHUNK_SIZE = 4096 unless defined?(CHUNK_SIZE)

class FailuresTest < Test::Unit::TestCase
  
  @@is_setup = false
  
  def setup_for_all
    unless @@is_setup
      #setup active record to use a sqlite database
      ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
  
      #load the database schema for this test
      load File.expand_path(File.dirname(__FILE__) + "/initech_dms/schema.rb")
  
      #require this plugin
      require "#{File.dirname(__FILE__)}/../init"
  
      FileStorage.class_eval do
        def self.backend
          @@backend ||= FileStorage::Backend::InMemory.new()
        end
      end
      @@is_setup = true
    end
  end
  
  def setup
    setup_for_all
  end
  
  def with_errors_on_get_chunk
    FileStorage::Backend::InMemory.class_eval do
      def get_chunk(file_id, chunk_number)
        raise IOError, "There was a problem!"
      end
    end    
    begin
      yield
    ensure
      FileStorage::Backend::InMemory.class_eval do
        remove_method(:get_chunk)
      end      
    end    
  end
  
  def test_size_of_data_received
    storable_class = new_storable_class
    storable_class.class_eval do
      def locator
        "locator_for_chunks_recieved_test"
      end
      def locate_attached_entity
        Object.new
      end
    end
    obj = storable_class.new
    obj.total_chunks = 5
    obj.size = 50
    ten_character_string = "some data."
    
    assert_equal(0, obj.size_of_data_received.to_i)
    assert !obj.file_done?
  
    #all but 1 chunk transferred

    assert_raises(IOError){ FileStorage.backend.get_chunk(obj.locator, 1) }
    obj.put_chunk(1, ten_character_string)
    assert_equal(ten_character_string, FileStorage.backend.get_chunk(obj.locator, 1))

    assert_raises(IOError){ FileStorage.backend.get_chunk(obj.locator, 2) }
    obj.put_chunk(2, ten_character_string)
    assert_equal(ten_character_string, FileStorage.backend.get_chunk(obj.locator, 2))

    obj.put_chunk(5, ten_character_string)
    obj.put_chunk(3, ten_character_string)    
    
    assert_equal([1, 2, 5, 3], obj.chunks_received)
    assert_equal(40, obj.size_of_data_received)
    
    with_errors_on_get_chunk do
      #Since we overrode the backend, the final chunk should cause an IOError while trying to assemble_chunks_into_a_file
      assert_raises(IOError){
        obj.put_chunk(4, ten_character_string)
      }
    end
    
    assert_equal([], obj.chunks_received, 
        "Chunks recieved should be empty because there was error in assembly (so start over)")
    assert_equal(0, obj.size_of_data_received, 
        "Size of data recieved should be zero because there was error in assembly (so start over)")
    
    #all the chunk should have been deleted!
    assert_raises(IOError){ FileStorage.backend.get_chunk(obj.locator, 1) }
    assert_raises(IOError){ FileStorage.backend.get_chunk(obj.locator, 2) }
    assert_raises(IOError){ FileStorage.backend.get_chunk(obj.locator, 3) }
    assert_raises(IOError){ FileStorage.backend.get_chunk(obj.locator, 4) }
    assert_raises(IOError){ FileStorage.backend.get_chunk(obj.locator, 5) }

    obj.put_chunk(1, ten_character_string)
    assert_equal(ten_character_string, FileStorage.backend.get_chunk(obj.locator, 1))    
  end
  
  def new_storable_class
    new_class = Class.new(ActiveRecord::Base)
    new_class.class_eval do
      set_table_name :managed_documents
      def self.column_names
        ["locator", "content_type", "file_name", "mime_type", "file_hash_type", "file_hash", 
          "size", "total_chunks", "chunks_received", "size_of_data_received", "lock_version"]
      end
    end
    new_class.send(:include, FileStorage::Storable)
    new_class
  end
  
  
  
end