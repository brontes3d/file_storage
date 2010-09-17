require 'test/unit'

require 'rubygems'
require 'activerecord'
require 'openssl'

#set rails env CONSTANT (we are not actually loading rails in this test, but activerecord depends on this constant)
RAILS_ENV = 'test' unless defined?(RAILS_ENV)
CHUNK_SIZE = 4096 unless defined?(CHUNK_SIZE)

class FileSystemBackendTest < Test::Unit::TestCase
  
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
          @@file_system_backend ||= FileStorage::Backend::FileSystem.new(
                File.join(ENV['CC_BUILD_ARTIFACTS'] || Dir.tmpdir, "filesystembackendtest-#{Process.pid}"))
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

    assert_equal(data_to_store, duplicate_report.data)    
    duplicate_report = TpsReport.find(duplicate_report.id)
    assert_equal(data_to_store, duplicate_report.data)
  end
  
  
  def test_file_stream_proc
    #setup
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }    
    tps_report = TpsReport.new
    tps_report.data = data_to_store
    tps_report.save!
    tps_report = TpsReport.find(tps_report.id)
    assert_equal(data_to_store, tps_report.data, "Expected to have stored the data in the tps report")
    
    #test
    fs_proc = tps_report.managed_document.file_stream_proc
    
    output_buffer = StringIO.new
    translation_proc = Proc.new do |input, out|
      # puts "running translation proc"
      # read_data = input.read
      # puts "translation proc reads: #{read_data.size}" 
      # out.write(input.read)
      while chunk = input.read(1003)
        # puts "read chunk"
        out.write(chunk)
      end
    end
    fs_proc.call(translation_proc, output_buffer)
    
    output_buffer.seek(0)
    
    wrote = output_buffer.read
    assert_equal(data_to_store.size, wrote.size)    
    assert_equal(data_to_store, wrote)    
  end
  
  def test_create_tps_report
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }
    file_hash = OpenSSL::Digest::SHA1.new(data_to_store).to_s
    
    tps_report = TpsReport.new
    tps_report.save!

    #incoming_chunked_file will created a StoredFile object and cause it to be saved
    managed_doc = tps_report.incoming_chunked_file!(data_to_store.size)
    
    file_path = FileStorage.backend.path_for_file(managed_doc.locator)
    assert(!File.exists?(file_path), 
          "Expecting no files to exist in the backend after incoming_chunked_file")

    assert_equal(1, managed_doc.start_chunk)
    
    offset = 0
    chunk_number = 1
    while(not managed_doc.file_done?)
      if(offset > data_to_store.size)
        flunk "We reached end of input before file was marked as done!"
      end
      managed_doc.put_chunk(chunk_number, data_to_store[offset, CHUNK_SIZE])
      offset += CHUNK_SIZE
      chunk_number += 1
    end
    managed_doc.update_file_hash

    assert managed_doc.matches_hash?(file_hash)
    file_path = FileStorage.backend.path_for_file(managed_doc.locator)
    assert_equal(data_to_store, File.read(file_path).to_s)
    
    assert(ManagedDocument.find(managed_doc.id))
    tps_report.destroy
    assert_raises(ActiveRecord::RecordNotFound){ ManagedDocument.find(managed_doc.id) }
    
    !File.exists?(file_path)
  end
  
  def test_rename_file
    data_to_store = %Q{
      Hey Peter,
      Whaaaat's happening--So.. I'm gonna have to go ahead and.. ask you to come in over the weekend.. ok...
      So, if you could go ahead and do that, that would be Greaaaat.
      - Lumberg
    }
    memo = Memo.new
    memo.bills_report_number = "123supergreat"
    memo.data = data_to_store
    
    file_path = FileStorage.backend.path_for_file("memo_123supergreat")    
    assert !File.exists?(file_path)
    memo.save!
    assert File.exists?(file_path)
  
    assert_equal(data_to_store, memo.data)
    assert_equal(data_to_store, File.read(file_path).to_s)
    
    FileStorage.backend.rename_file("memo_123supergreat", "Memo_123supergreat")
    
    file_path_new = FileStorage.backend.path_for_file("Memo_123supergreat")
    assert File.exists?(file_path_new)
    
    FileStorage.backend.rename_file("Memo_123supergreat", "againmemo_123supergreat")
    
    file_path_new_again = FileStorage.backend.path_for_file("againmemo_123supergreat")
    assert File.exists?(file_path_new_again)    
    assert !File.exists?(file_path)
    assert !File.exists?(file_path_new)
  end
  
  
  def test_create_memo
    data_to_store = %Q{
      Hey Peter,
      Whaaaat's happening--So.. I'm gonna have to go ahead and.. ask you to come in over the weekend.. ok...
      So, if you could go ahead and do that, that would be Greaaaat.
      - Lumberg
    }
    memo = Memo.new
    memo.bills_report_number = "123supergreat"
    memo.data = data_to_store
    
    file_path = FileStorage.backend.path_for_file("memo_123supergreat")    
    assert !File.exists?(file_path)
    memo.save!
    assert File.exists?(file_path)
  
    assert_equal(data_to_store, memo.data)
    assert_equal(data_to_store, File.read(file_path).to_s)
  
    memo.data = "-Censored-"
    assert_equal(data_to_store, File.read(file_path).to_s)
    memo.save!
    assert_equal("-Censored-", File.read(file_path).to_s)
  
    managed_doc = memo.managed_document
    assert(ManagedDocument.find(managed_doc.id))
    memo.destroy
    assert_raises(ActiveRecord::RecordNotFound){ ManagedDocument.find(managed_doc.id) }
    !File.exists?(file_path)
  end
  
  def test_create_cover_sheet
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSCoverSheet.pdf", "r"){ |file| file.read }
    cover_sheet = TpsCoverSheet.new
    cover_sheet.test_number = 43234

    #TODO: this has changed, test the new behavior:
    # assert_raises(ArgumentError){ cover_sheet.data = data_to_store }
    
    file_path = FileStorage.backend.path_for_file("tps_cover_sheet_43234")
    
    assert !File.exists?(file_path)
    cover_sheet.save!
    assert_equal(nil, cover_sheet.managed_document)
    
    cover_sheet.data = data_to_store
    assert File.exists?(file_path)
    
    assert_equal(cover_sheet.data, data_to_store)
    cover_sheet.save!
    assert_equal(cover_sheet.data, data_to_store)

    managed_doc = cover_sheet.managed_document
    assert(ManagedDocument.find(managed_doc.id))
    cover_sheet.destroy
    assert_raises(ActiveRecord::RecordNotFound){ ManagedDocument.find(managed_doc.id) }
    !File.exists?(file_path)
  end

  def test_status
    assert_nothing_raised(Exception) { FileStorage.backend.status }

    # set the dir to read only
    FileUtils.chmod 0555, FileStorage.backend.base_path

    # should not be able to write new data
    assert_raise(IOError) { FileStorage.backend.status }

    # fix the store for future tests
    FileUtils.chmod 0755, FileStorage.backend.base_path
  end
end
