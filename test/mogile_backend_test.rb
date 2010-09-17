require 'test/unit'

require 'rubygems'
require 'activerecord'
require 'openssl'

#set rails env CONSTANT (we are not actually loading rails in this test, but activerecord depends on this constant)
RAILS_ENV = 'test' unless defined?(RAILS_ENV)
CHUNK_SIZE = 4096 unless defined?(CHUNK_SIZE)

MAX_READ_SIZE_FOR_MOGILE_TEST = 65536

class MogileBackendTest < Test::Unit::TestCase
  
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

  def test_stream_proc_why_arent_we_filling_the_pipe
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }        
        
    tps_report = TpsReport.new
    tps_report.data = data_to_store
    tps_report.save!
    tps_report = TpsReport.find(tps_report.id)
    assert_equal(data_to_store.size, tps_report.data.size, "Expected to have stored the data in the tps report")
    assert_equal(data_to_store, tps_report.data, "Expected to have stored the data in the tps report")
    
    #test
    fs_proc = tps_report.managed_document.file_stream_proc
    
    # puts "\n\n\n\n\n\n\nOK, now test for real...\n\n\n\n\n\n\n"
    
    reads_done = 0
    output_buffer = StringIO.new
    translation_proc = Proc.new do |input, out|
      # puts "running translation proc"
      # read_data = input.read
      # puts "translation proc reads: #{read_data.size}" 
      # out.write(input.read)
      begin
      
      while chunk = input.read(1003)
        # puts "read chunk"
        out.write(chunk)
        reads_done += 1
        # sleep(0.5)        
      end
      
      rescue => e
        puts e.inspect
        puts e.backtrace.join("\n")
      end
    end
    
    fs_proc.call(translation_proc, output_buffer)
    
    output_buffer.seek(0)
    
    wrote = output_buffer.read
    assert_equal(data_to_store.size, wrote.size)    
    assert_equal(data_to_store, wrote)    
  end
  
  # Unreliable test... :0(
  #
  # created only so I could inspect the error message output during a broken download (as I added more logging)
  #
  # def test_error_thrown_from_underlying_socket_in_rfuzz
  #   data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }        
  #       
  #   tps_report = TpsReport.new
  #   tps_report.data = data_to_store
  #   tps_report.save!
  #   tps_report = TpsReport.find(tps_report.id)
  #   assert_equal(data_to_store, tps_report.data, "Expected to have stored the data in the tps report")
  #   
  #   #test
  #   fs_proc = tps_report.managed_document.file_stream_proc
  #   
  #   crush_the_socket = Proc.new do
  #     RFuzz::PushBackIO.class_eval do
  #       def read(*args)
  #         raise RFuzz::HttpClientError, "test when mogile goes bad"
  #       end
  #     end
  #   end
  #   reads_done = 0
  #   
  #   output_buffer = StringIO.new
  #   translation_proc = Proc.new do |input, out|
  #     # puts "running translation proc"
  #     # read_data = input.read
  #     # puts "translation proc reads: #{read_data.size}" 
  #     # out.write(input.read)
  #     while chunk = input.read(1003)
  #       # puts "read chunk"
  #       out.write(chunk)
  #       reads_done += 1
  #       
  #       if reads_done > 100
  #         crush_the_socket.call
  #       end
  #     end
  #   end
  #   
  #   assert_raises(IOError){
  #     fs_proc.call(translation_proc, output_buffer)
  #   }
  # end
  
  def test_read_write_limits
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }        
    # data_to_store = "hi bob"
    
    tempfile_to_store = Tempfile.new("tpsreport")
    tempfile_to_store << data_to_store
    tempfile_to_store.seek(0)
    
    # puts "Tempfile is: " + tempfile_to_store.inspect + " size: " + tempfile_to_store.size.inspect    
    # puts "TPS report size: " + data_to_store.size.inspect + " vs. " + FileStorage.max_read_size.inspect
    
    TCPSocket.class_eval do
      cattr_accessor :reads_and_writes_too_big
      def report_on_read_or_write(method, size)
        # # STDERR.puts "#{method} called: " + arg.size.inspect
        if size > FileStorage.max_read_size
          TCPSocket.reads_and_writes_too_big ||= []
          begin
            raise "\n\nInvariance Failure! #{method} too big (max is #{FileStorage.max_read_size}): " + size.inspect
          rescue => e
            # TCPSocket.reads_and_writes_too_big << e
            STDERR.puts e.message
            STDERR.puts e.backtrace.join("\n")
          end
        end
      end
      alias_method :orig_write, :write
      def write(arg)
        report_on_read_or_write(:write, arg.size) if arg
        orig_write(arg)
      end
      alias_method :orig_read, :read
      def read(*args)
        result = orig_read(*args)
        report_on_read_or_write(:read, result.size) if result
        result
      end
    end
    TCPSocket.reads_and_writes_too_big = []
    
    tps_report = TpsReport.new
    tps_report.data = tempfile_to_store
    tps_report.save!
    tps_report = TpsReport.find(tps_report.id)
    assert_equal(data_to_store.size, tps_report.data.size)
    assert_equal(data_to_store, tps_report.data)
    
    TCPSocket.class_eval do
      alias_method :write, :orig_write    
      alias_method :read, :orig_read
    end
    
    TCPSocket.reads_and_writes_too_big.each do |ex|
      assert_nothing_raised{
        raise ex
      }
    end
  end



  
  def test_file_stream_proc
    #setup
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }        
        
    tps_report = TpsReport.new
    tps_report.data = data_to_store
    tps_report.save!
    tps_report = TpsReport.find(tps_report.id)
    assert_equal(data_to_store.size, tps_report.data.size, "Expected to have stored the data in the tps report")
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

  # test/mogile_backend_test.rb:114:in `read'
  # /Library/Ruby/Gems/1.8/gems/rfuzz-0.9/lib/rfuzz/pushbackio.rb:67:in `read'
  # /Library/Ruby/Gems/1.8/gems/rfuzz-0.9/lib/rfuzz/pushbackio.rb:98:in `protect'
  # /Library/Ruby/Gems/1.8/gems/rfuzz-0.9/lib/rfuzz/pushbackio.rb:67:in `read'
  # /Library/Ruby/Gems/1.8/gems/rfuzz-0.9/lib/rfuzz/client.rb:358:in `read_response'
  # /Library/Ruby/Gems/1.8/gems/rfuzz-0.9/lib/rfuzz/client.rb:455:in `notify'
  # /Library/Ruby/Gems/1.8/gems/rfuzz-0.9/lib/rfuzz/client.rb:351:in `read_response'
  # /Library/Ruby/Gems/1.8/gems/rfuzz-0.9/lib/rfuzz/client.rb:390:in `send_request'
  # /Library/Ruby/Gems/1.8/gems/rfuzz-0.9/lib/rfuzz/client.rb:408:in `method_missing'
  # ./test/../lib/file_storage/backend/mogilefs_storage.rb:78:in `file_stream_proc'
  # ./test/../lib/file_storage/backend/base.rb:128:in `call'
  # ./test/../lib/file_storage/backend/base.rb:128:in `file_hash'
  # ./test/../lib/file_storage/storable.rb:160:in `update_file_hash'
  # ./test/../lib/file_storage/storable.rb:115:in `put_chunk_unsafe'
  # ./test/../lib/file_storage/storable.rb:88:in `put_chunk'
  # /Library/Ruby/Gems/1.8/gems/activerecord-2.1.0/lib/active_record/associations/association_proxy.rb:177:in `send'
  # /Library/Ruby/Gems/1.8/gems/activerecord-2.1.0/lib/active_record/associations/association_proxy.rb:177:in `method_missing'
  # test/mogile_backend_test.rb:138:in `test_create_tps_report'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testcase.rb:78:in `__send__'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testcase.rb:78:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:34:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:33:in `each'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:33:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:34:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:33:in `each'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:33:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/ui/testrunnermediator.rb:46:in `run_suite'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/ui/console/testrunner.rb:67:in `start_mediator'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/ui/console/testrunner.rb:41:in `start'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/ui/testrunnerutilities.rb:29:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/autorunner.rb:216:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/autorunner.rb:12:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit.rb:278
  # test/mogile_backend_test.rb:214
  
  # test/mogile_backend_test.rb:142:in `write'
  # /Library/Ruby/Gems/1.8/gems/mogilefs-client-1.2.1/lib/mogilefs/httpfile.rb:78:in `close'
  # /Library/Ruby/Gems/1.8/gems/mogilefs-client-1.2.1/lib/mogilefs/httpfile.rb:49:in `open'
  # /Library/Ruby/Gems/1.8/gems/mogilefs-client-1.2.1/lib/mogilefs/mogilefs.rb:135:in `new_file'
  # /Library/Ruby/Gems/1.8/gems/mogilefs-client-1.2.1/lib/mogilefs/mogilefs.rb:163:in `store_content'
  # ./test/../lib/file_storage/backend/mogilefs_storage.rb:58:in `put_file'
  # ./test/../lib/file_storage/backend/base.rb:144:in `assemble_chunks_into_a_file'
  # ./test/../lib/file_storage/storable.rb:114:in `put_chunk_unsafe'
  # ./test/../lib/file_storage/storable.rb:88:in `put_chunk'
  # /Library/Ruby/Gems/1.8/gems/activerecord-2.1.0/lib/active_record/associations/association_proxy.rb:177:in `send'
  # /Library/Ruby/Gems/1.8/gems/activerecord-2.1.0/lib/active_record/associations/association_proxy.rb:177:in `method_missing'
  # test/mogile_backend_test.rb:180:in `test_create_tps_report'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testcase.rb:78:in `__send__'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testcase.rb:78:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:34:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:33:in `each'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:33:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:34:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:33:in `each'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:33:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/ui/testrunnermediator.rb:46:in `run_suite'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/ui/console/testrunner.rb:67:in `start_mediator'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/ui/console/testrunner.rb:41:in `start'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/ui/testrunnerutilities.rb:29:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/autorunner.rb:216:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/autorunner.rb:12:in `run'
  # /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit.rb:278
  # test/mogile_backend_test.rb:256
  
  
  def test_create_tps_report
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc", "r"){ |file| file.read }
        
    file_hash = OpenSSL::Digest::SHA1.new(data_to_store).to_s
    
    tps_report = TpsReport.new
    tps_report.save!

    managed_doc = tps_report.incoming_chunked_file!(data_to_store.size)
    
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

    assert(ManagedDocument.find(managed_doc.id))
    tps_report.destroy
    assert_raises(ActiveRecord::RecordNotFound){ ManagedDocument.find(managed_doc.id) }
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
    
    memo.save!
    
  
    assert_equal(data_to_store.size, memo.data.size)
    assert_equal(data_to_store, memo.data)
    assert_equal(data_to_store.size, FileStorage.backend.get_file("memo_123supergreat").size)
    assert_equal(data_to_store, FileStorage.backend.get_file("memo_123supergreat"))
  
    memo.data = "-Censored-"
    memo.save!

    assert_equal("-Censored-", FileStorage.backend.get_file("memo_123supergreat"))
  
    managed_doc = memo.managed_document
    assert(ManagedDocument.find(managed_doc.id))
    memo.destroy
    assert_raises(ActiveRecord::RecordNotFound){ ManagedDocument.find(managed_doc.id) }
    
    assert_raises(IOError){
      FileStorage.backend.get_file("memo_123supergreat").inspect
    }
  end

  def test_create_cover_sheet
    data_to_store = File.open("#{File.dirname(__FILE__)}/initech_dms/TPSCoverSheet.pdf", "r"){ |file| file.read }
    cover_sheet = TpsCoverSheet.new
    cover_sheet.test_number = 43234
      
    cover_sheet.save!
    assert_equal(nil, cover_sheet.managed_document)
    
    cover_sheet.data = data_to_store
    
    assert_equal(cover_sheet.data.size, data_to_store.size)
    assert_equal(cover_sheet.data, data_to_store)
    cover_sheet.save!
    assert_equal(cover_sheet.data.size, data_to_store.size)
    assert_equal(cover_sheet.data, data_to_store)
  
    managed_doc = cover_sheet.managed_document
    assert(ManagedDocument.find(managed_doc.id))
    cover_sheet.destroy
    assert_raises(ActiveRecord::RecordNotFound){ ManagedDocument.find(managed_doc.id) }
  end
  
  # TODO: fix this test. the backend complains about FILE_STORAGE_MOGILEFS_CONFIG
  # def test_status_should_work
  #   status = @@mogile_backend.status
  #   assert(status.include?('OK'), "status did not succeed; returned '#{status}'")
  # end

  def test_raw_put_get_and_delete
    test_string = Time.now.to_f.to_s
    file_name = "MogileFSTest-#{Process.pid}-#{test_string}"
    assert_nothing_raised(Exception) { @@mogile_backend.put_file(file_name, test_string) }
    raise "MogileFS test failed" unless @@mogile_backend.get_file(file_name) == test_string
    assert_nothing_raised(Exception) { @@mogile_backend.delete_file(file_name) }
  end

  def test_get_file_after_storage_failure
    MogileFS::MogileFS.class_eval do
      alias_method :original_store_content, :store_content
      def store_content(*args)
        raise IOError, 'store content is broken'
      end
    end

    test_string = Time.now.to_f.to_s
    file_name = "MogileFSTest-#{Process.pid}-#{test_string}"
    assert_raise(IOError) do
      @@mogile_backend.put_file(file_name, test_string)
    end

    MogileFS::MogileFS.class_eval do
      alias_method :store_content, :original_store_content
    end
  end
end
