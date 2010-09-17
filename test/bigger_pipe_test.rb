require 'test/unit'

require 'rubygems'
require 'activerecord'
require 'openssl'

class BiggerPipeTest < Test::Unit::TestCase
  
  @@is_setup = false
  
  def setup_for_all
    unless @@is_setup
      #require this plugin
      require "#{File.dirname(__FILE__)}/../init"
      @@is_setup = true
    end
  end
  
  def setup
    setup_for_all
  end

  def test_write_all_then_read_all
    some_data = "abcdefghijklmnopqrstuvwxyz"
    r, w = BiggerPipe.pipe
    
    w.write(some_data)
    w.close
    result = r.read
    r.close
    
    assert_equal(some_data.size, result.size)
    assert_equal(some_data, result)
  end

  def test_reader_and_writer_thread
    some_data = File.read("#{File.dirname(__FILE__)}/initech_dms/TPSReport.doc")
    r, w = BiggerPipe.pipe
    
    write_from_this_string_io = StringIO.new(some_data)
    write_finished = false
    writer_thread = Thread.new do
      begin
        while write = write_from_this_string_io.read(1024)
          w.write(write)
        end
      rescue => e
        puts e.inspect
        puts e.backtrace.join("\n")
      ensure
        w.close
        write_finished = true
      end
    end
    
    read_into_this_buffer = ""
    read_finished = false
    reader_thread = Thread.new do
      begin     
        while read = r.read(1024)
          read_into_this_buffer += read
        end
      rescue => e
        puts e.inspect
        puts e.backtrace.join("\n")
      ensure
        r.close
        read_finished = true
      end
    end
    
    while(!write_finished || !read_finished) do
      Thread.pass
    end
    
    assert_equal(some_data.size, read_into_this_buffer.size)
    assert_equal(some_data, read_into_this_buffer)
  end
  
  def test_write_faster_than_you_read
    some_data = "abcdefghijklmnopqrstuvwxyz"
    r, w = BiggerPipe.pipe
    
    write_from_this_string_io = StringIO.new(some_data)
    write_finished = false
    writer_thread = Thread.new do
      while write = write_from_this_string_io.read(5)
        w.write(write)
      end
      w.close
      write_finished = true
    end
    
    read_into_this_buffer = ""
    read_finished = false
    reader_thread = Thread.new do
      sleep(0.5)
      while read = r.read(1)
        sleep(0.02)
        read_into_this_buffer += read
      end
      r.close
      read_finished = true
    end
    
    while(!write_finished || !read_finished) do
      Thread.pass
    end
    
    assert_equal(some_data.size, read_into_this_buffer.size)
    assert_equal(some_data, read_into_this_buffer)
  end

  def test_read_faster_than_you_write
    some_data = "abcdefghijklmnopqrstuvwxyz"
    r, w = BiggerPipe.pipe
    
    write_from_this_string_io = StringIO.new(some_data)
    write_finished = false
    writer_thread = Thread.new do
      sleep(0.5)
      while write = write_from_this_string_io.read(5)
        sleep(0.02)
        w.write(write)
      end
      w.close
      write_finished = true
    end
    
    read_into_this_buffer = ""
    read_finished = false
    reader_thread = Thread.new do
      while read = r.read(5)
        read_into_this_buffer += read
      end
      r.close
      read_finished = true
    end
    
    while(!write_finished || !read_finished) do
      Thread.pass
    end
    
    assert_equal(some_data.size, read_into_this_buffer.size)
    assert_equal(some_data, read_into_this_buffer)
  end

  def test_read_all_before_you_write
    some_data = "abcdefghijklmnopqrstuvwxyz"
    r, w = BiggerPipe.pipe
    
    write_from_this_string_io = StringIO.new(some_data)
    write_finished = false
    writer_thread = Thread.new do
      while write = write_from_this_string_io.read(1)
        sleep(0.02)
        w.write(write)
      end
      w.close
      write_finished = true
    end
    
    read_into_this_buffer = ""
    read_finished = false
    reader_thread = Thread.new do
      read_into_this_buffer = r.read
      r.close
      read_finished = true
    end
    
    while(!write_finished || !read_finished) do
      Thread.pass
    end
    
    assert_equal(some_data.size, read_into_this_buffer.size)
    assert_equal(some_data, read_into_this_buffer)
  end


end
