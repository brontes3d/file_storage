require 'test/unit'

require 'rubygems'
require 'activerecord'

#set rails env CONSTANT (we are not actually loading rails in this test, but activerecord depends on this constant)
RAILS_ENV = 'test' unless defined?(RAILS_ENV)
CHUNK_SIZE = 4096 unless defined?(CHUNK_SIZE)

class FileStorageTest < Test::Unit::TestCase
  
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
          @@backend ||= FileStorage::Backend::InMemory.new()
        end
      end
      @@is_setup = true
    end
  end
  
  def setup
    setup_for_all
  end
  
  def test_duplicate_file
    # data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }
    data_to_store = "hi"
    
    tps_report = TpsReport.new
    tps_report.data = data_to_store
    tps_report.save!
    
    tps_report = TpsReport.find(tps_report.id)
    
    assert_equal(data_to_store, tps_report.data)
    
    duplicate_report = TpsReport.new
    duplicate_report.save!
    duplicate_report.copy_data_from(tps_report)
    
    assert_equal(data_to_store, duplicate_report.data, "Data should be equal after copied")
    duplicate_report = TpsReport.find(duplicate_report.id)
    assert_equal(data_to_store, duplicate_report.data, "Data should be equal after reload")
  end
    
  def test_locate_attached_entity_on_tps_reports
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }
    
    tps_report = TpsReport.new
    
    base_assertion = Proc.new do |on_report|
      assert on_report.file_storage_via_assoc,
        "Expecting tps_report.file_storage_via_assoc to not be nil"
      assert on_report.file_storage_via_assoc.is_a?(ManagedDocument),
        "Expecting tps_report.file_storage_via_assoc to not be a ManagedDocument"

      assert_equal(on_report.file_storage_via_assoc, on_report.managed_document,
        "file_storage_via_assoc should be the same thing as managed_document")

      assert_equal(on_report, tps_report.file_storage_via_assoc.locate_attached_entity,
        "locate_attached_entity should return the same tps_report")
    end
    
    assertions_on_a_tps_report = Proc.new do |on_report|
      base_assertion.call(on_report)
      
      if on_report.id
        refetched = TpsReport.find(on_report.id)
        base_assertion.call(refetched)
      end
    end
    
    assertions_on_a_tps_report.call(tps_report)
    
    tps_report.file_name = "superimportant.doc"
    tps_report.save!
    
    assertions_on_a_tps_report.call(tps_report)
    
    tps_report.data = data_to_store
    
    assertions_on_a_tps_report.call(tps_report)
    
    tps_report.save!
    
    assertions_on_a_tps_report.call(tps_report)
    
  end
  
  def test_create_tps_report
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }
    file_hash = OpenSSL::Digest::SHA1.new(data_to_store).to_s
    
    tps_report = TpsReport.new
    tps_report.file_name = "superimportant.doc"
    tps_report.save!

    #incoming_chunked_file will created a StoredFile object and cause it to be saved
    managed_doc = tps_report.incoming_chunked_file!(data_to_store.size)
    # TODO: backends should raise IOError when trying to get a file which does not exist
    assert_raises(IOError, "file should not exist in backend"){
      FileStorage.backend.get_file(managed_doc.locator)
    }

    assert_equal(1, managed_doc.start_chunk)
    
    offset = 0
    chunk_number = 1
    while(not managed_doc.file_done?)
      if(offset > data_to_store.size)
        flunk "We reached end of input before file was marked as done!"
      end
      managed_doc.put_chunk(chunk_number, data_to_store[offset, CHUNK_SIZE])
      #TODO "would be cute" to support this:
        # managed_doc.chunks[chunk_number] = data_to_store[offset, CHUNK_SIZE]
      
      offset += CHUNK_SIZE
      chunk_number += 1
    end
    managed_doc.update_file_hash

    assert managed_doc.matches_hash?(file_hash), "Expected backend-generated hash to match hash calculated in test"
    assert_equal(data_to_store, FileStorage.backend.get_file(managed_doc.locator), "file in backend should exist")
    
    assert(ManagedDocument.find(managed_doc.id))
    tps_report.destroy
    assert_raises(ActiveRecord::RecordNotFound){ ManagedDocument.find(managed_doc.id) }
    
    # TODO: backends should raise IOError when trying to get a file which does not exist
    assert_raises(IOError, "file should not exist in backend"){
      FileStorage.backend.get_file(managed_doc.locator)
    }
  end
  
  def test_create_memo
    data_to_store = %Q{
      Hey Peter,
      Whaaaat's happening--So.. I'm gonna have to go ahead and.. ask you to come in over the weekend.. ok...
      So, if you could go ahead and do that, that would be Greaaaat.
      - Lumberg
    }
    file_hash = OpenSSL::Digest::SHA1.new(data_to_store).to_s
    memo = Memo.new
    memo.bills_report_number = "123supergreat"    
    file_locator = "memo_123supergreat"
    assert_equal(nil, memo.data)    
    memo.data = data_to_store
    
    # assert_equal(file_hash, memo.file_hash)
    
    # TODO: backends should raise IOError when trying to get a file which does not exist
    assert_raises(IOError, "file should not exist in backend"){
      FileStorage.backend.get_file(file_locator)
    }
    memo.save!

    assert_equal(file_hash, memo.file_hash)

    assert_equal(data_to_store, FileStorage.backend.get_file(file_locator), "file should be in backend")
  
    assert_equal(data_to_store, memo.data)
    assert_equal(data_to_store, FileStorage.backend.get_file(file_locator), "file should be in backend")
  
    memo.data = "-Censored-"
    assert_equal(data_to_store, FileStorage.backend.get_file(file_locator), "file should be in backend")
    memo.save!
    assert_equal("-Censored-", FileStorage.backend.get_file(file_locator), "file should be in backend")

    assert_equal("-Censored-", memo.data)
    memo = Memo.find(memo.id)
    assert_equal("-Censored-", memo.data)
  
    managed_doc = memo.managed_document
    assert(ManagedDocument.find(managed_doc.id))
    memo.destroy
    assert_raises(ActiveRecord::RecordNotFound){ ManagedDocument.find(managed_doc.id) }
    # TODO: backends should raise IOError when trying to get a file which does not exist
    assert_raises(IOError, "file should not exist in backend"){
      FileStorage.backend.get_file(file_locator)
    }    
  end
  
  def test_create_cover_sheet
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSCoverSheet.pdf", "r"){ |file| file.read }
    cover_sheet = TpsCoverSheet.new
    cover_sheet.test_number = 43234

    #TODO: this has changed, test the new behavior:
    # assert_raises(ArgumentError){ cover_sheet.data = data_to_store }
    
    # TODO: backends should raise IOError when trying to get a file which does not exist
    assert_raises(IOError, "file should not exist in backend"){
      FileStorage.backend.get_file("tps_cover_sheet_43234")
    }
    cover_sheet.save!
    assert_equal(nil, cover_sheet.managed_document)
    
    cover_sheet.data = data_to_store
    assert_equal(data_to_store, FileStorage.backend.get_file("tps_cover_sheet_43234"), "file in backend should exist")
    
    assert_equal(cover_sheet.data, data_to_store)
    cover_sheet.save!
    assert_equal(cover_sheet.data, data_to_store)

    managed_doc = cover_sheet.managed_document
    assert(ManagedDocument.find(managed_doc.id))
    cover_sheet.destroy
    assert_raises(ActiveRecord::RecordNotFound){ ManagedDocument.find(managed_doc.id) }
    # TODO: backends should raise IOError when trying to get a file which does not exist
    assert_raises(IOError, "file should not exist in backend"){
      FileStorage.backend.get_file("tps_cover_sheet_43234")
    }
  end
  
  #test Storable include
  def test_storable_class_inclusion_errors
    #test that there is a check for required columns
    tocheck = Class.new(ActiveRecord::Base)
    tocheck.class_eval do
      def self.column_names
        []
      end
    end
    assert_raises(ArgumentError){ tocheck.send(:include, FileStorage::Storable) }
  end
  
  # def test_storable_ensure_existance_of_file_in_backend
  #   storable_class = new_storable_class
  #   storable_class.class_eval do
  #     def locator
  #       "locator_for_test"
  #     end
  #   end
  #   obj = storable_class.new
  #   file_path = FileStorage.backend.path_for_file("locator_for_test")
  #   assert !File.exists?(file_path)
  #   obj.ensure_existance_of_file_in_backend
  #   assert File.exists?(file_path)    
  # end
  
  def test_start_chunk
    storable_class = new_storable_class
    storable_class.class_eval do
      def total_chunks
        10
      end
    end
    obj = storable_class.new
    assert_equal(1, obj.start_chunk)
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
  
    #after 1 chunk transfered
    obj.put_chunk(1, ten_character_string)
    assert_equal(10, obj.size_of_data_received)
    assert !obj.file_done?
  
    #after another chunk
    obj.put_chunk(2, ten_character_string)
    assert_equal(20, obj.size_of_data_received)
    assert !obj.file_done?
    
    #after another chunk (out of order)
    obj.put_chunk(5, ten_character_string)
    assert_equal(30, obj.size_of_data_received)
    assert !obj.file_done?

    #after final chunks
    obj.put_chunk(3, ten_character_string)
    obj.put_chunk(4, ten_character_string)
    assert_equal(50, obj.size_of_data_received)
    assert obj.file_done?
  end
  
  def test_all_chunks_recieved
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
    obj.size = 24
    obj.total_chunks = 2
  
    #for a new file -- false
    assert !obj.all_chunks_received?
  
    #after 1 chunk transfered -- false
    obj.put_chunk(1, "some data...")
    assert !obj.all_chunks_received?
  
    #after all chunks transfered -- true
    obj.put_chunk(2, "more data...")
    assert obj.all_chunks_received?
  end
  
  def test_put_chunk
    storable_class = new_storable_class
    storable_class.class_eval do
      def locator
        "locator_for_put_chunk_test"
      end
      def locate_attached_entity
        Object.new
      end
    end
    #3 chunks total
    
    #at first, no file should exist
    
    #after putting 1 chunk that chunk file should exists
    
    #after putting 3rd chunk, 1st and 3rd chunk files should exists, but not 2nd and not full file
    
    #after putting 2nd chunk, no more chunk files should exist, and final file should be complete
    
  end
  
  #TODO: think about how we can make this test work, I think it is chocking on ActiveRecord is not thread safe
  # #Test, chunk-wise file storage in multiple threads
  # #we think there might be a bug if 2 seperate threads put the final chunk at the same time
  # #we can fix this at this level for file retrieval
  # def test_concurrent_chunk_transfer
  #   
  #   #put the odd chunks in one thread
  #   
  #   #put the even chunks in another thread
  #   
  #   #start by just putting all the chunks and testing that the file exists
  #   data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }
  #   
  #   tps_report = TpsReport.new
  #   tps_report.save!
  # 
  #   #incoming_chunked_file will created a StoredFile object and cause it to be saved
  #   managed_doc = tps_report.incoming_chunked_file(data_to_store.size)
  #   
  #   file_path = FileStorage.backend.path_for_file(managed_doc.locator)
  #   
  #   get_data_for = Proc.new do |chunknum|
  #     data_to_store[(chunknum-1)*CHUNK_SIZE, CHUNK_SIZE]
  #   end
  #   
  #   puts "total chunks: " + managed_doc.total_chunks.inspect
  #   
  #   t1_chunk_number = 1
  #   t2_chunk_number = 2
  #   t1_done = false
  #   t2_done = false
  #   Thread.new do
  #     while(t1_chunk_number <= managed_doc.total_chunks)
  #       puts "putting chunk t1 #{t1_chunk_number}"
  #       managed_doc.put_chunk(t1_chunk_number, get_data_for.call(t1_chunk_number))
  #       t1_chunk_number += 2
  #     end
  #     t1_done = true
  #     puts "done t1"
  #   end
  #   Thread.new do    
  #     while(t2_chunk_number <= managed_doc.total_chunks)
  #       puts "putting chunk t2 #{t2_chunk_number}"
  #       managed_doc.put_chunk(t2_chunk_number, get_data_for.call(t2_chunk_number))
  #       t2_chunk_number += 2
  #     end
  #     t2_done = true
  #     puts "done t2"
  #   end
  #   
  #   while(!t1_done or !t2_done)
  #     Thread.pass
  #   end
  #   
  #   # assert_equal(data_to_store, tps_report.data)
  #   assert_equal(data_to_store.size, File.size(file_path))
  # end
  # #but the other worry is in sending a file-transfer-complete.. (but I guess the device transfer retry should cover that problem)
  
  
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
