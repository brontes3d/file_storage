class FileStorage::Backend::InMemory < FileStorage::Backend::Base
  @@file_store = {}
  
  def initialize
    unless RAILS_ENV == "test"
      raise ArgumentError, 
              "The in-memory backend is for testing purposes only! No other environments allowed. "+
              "Exepected RAILS_ENV to be 'test', but got '#{RAILS_ENV}'"
    end
    super
  end

  def status
    'backend OK'
  end

  def file_exists?(file_id)
    !@@file_store[file_id].nil?
  end
  
  # def put_file_from_read_proc(file_id, total_size, read_proc)
  #   @@file_store[file_id] = ""
  #   while to_write = read_proc.call
  #     @@file_store[file_id] += to_write
  #   end
  # end
  
  def callback_to_write_proc(file_id, write_callback)
    unless @@file_store[file_id]
      raise IOError, "file doesn't exist in backend for file_id '#{file_id}'"          
    end
    write_callback.call(@@file_store[file_id])
  end

  def put_file_from_write_proc(file_id, total_size, write_proc)
    @@file_store[file_id] = ""
    write_proc.call(Proc.new do |to_write|
      @@file_store[file_id] += to_write
    end)
  end
    
  def delete_file(file_id)
    @@file_store[file_id] = nil
  end
  
end
