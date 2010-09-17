#In order to run this test: you must... mysqladmin create concurrency_test -u root

require 'test/unit'

require 'rubygems'
require 'activerecord'
require 'tempfile'

#set rails env CONSTANT (we are not actually loading rails in this test, but activerecord depends on this constant)
RAILS_ENV = 'test' unless defined?(RAILS_ENV)
CHUNK_SIZE = 4096 unless defined?(CHUNK_SIZE)

DIR_FOR_CONCURRENT_TEST = ENV['CC_BUILD_ARTIFACTS'] || Dir.tmpdir

class ConcurrentChunkWriteTest < Test::Unit::TestCase
  
  @@is_setup = false
  
  def setup_for_all
    unless @@is_setup
      ActiveRecord::Base.configurations = YAML.load_file(File.dirname(__FILE__) + "/mysql_db.yml")
      ActiveRecord::Base.establish_connection
      load File.expand_path(File.dirname(__FILE__) + "/schema.rb")
      load File.expand_path(File.dirname(__FILE__) + "/shared.rb")
      @@is_setup = true
    end
  end
  
  def setup
    setup_for_all
  end
  
  def run_put_chunks(storable_thing_id, write_every, out_of_every, data_to_write)
    r = `ruby #{File.dirname(__FILE__)}/put_chunks.rb #{DIR_FOR_CONCURRENT_TEST} #{storable_thing_id} #{write_every} #{out_of_every} #{data_to_write}`
    # puts "run output : " + r
    r.split("\n").last
  end
  
  def test_one_after_the_other
    wt = WithStorageThing.create!
    wt.incoming_chunked_file!(1000)
    wt.storable_thing.total_chunks = 50
    wt.storable_thing.save!
        
    run_put_chunks(wt.storable_thing.id, 1, 2, "abcdefghijklmnopqrst") #must be chunk of 20 because 1000/50 = 20 (total size / total chunks)
    run_put_chunks(wt.storable_thing.id, 2, 2, "abcdefghijklmnopqrst")
    
    st = StorableThing.find(wt.storable_thing.id)
    # puts "st: " + st.inspect
    assert st.file_done?
  end
  
  def test_two_at_a_time
    wt = WithStorageThing.create!
    wt.incoming_chunked_file!(1000)
    wt.storable_thing.total_chunks = 50
    wt.storable_thing.save!
    
    # puts "wt.storable_thing: " + wt.storable_thing.inspect
    
    #data_to_write must be 20 bytes because 1000/50 = 20 (total size / total chunks)
    data_to_write = "abcdefghijklmnopqrst"
    
    r1, r2, r3 = nil
    a = Thread.new do
      r1 = run_put_chunks(wt.storable_thing.id, 1, 3, data_to_write)
    end
    b = Thread.new do
      r2 = run_put_chunks(wt.storable_thing.id, 2, 3, data_to_write)
    end
    c = Thread.new do
      r3 = run_put_chunks(wt.storable_thing.id, 3, 3, data_to_write)
    end
    a.join
    b.join
    c.join
    
    results = [r1, r2, r3]
    
    assert_equal(["false", "false", "true"], results.sort!, 
      "Expcted that out of three threads concurrently writing chunks, "+
      "exactly one should have reported that the file was done when it was done putting chunks. "+
      "Instead got: #{results.inspect}")
    
    st = StorableThing.find(wt.storable_thing.id)
    # puts "st: " + st.inspect
    
    assert st.file_done?
  end
  

end