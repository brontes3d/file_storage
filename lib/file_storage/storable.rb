# Include this module in the ActiveRecord model you use for storing metadata about your stored file
# model is require to implement the following columns:
# * locator -- string column used to store unique identitifier for locating file in backend
# * file_hash_type -- string column storing the type of hash stored in the file_hash column
# * file_hash -- string column storing a hash of the contents of the stored file data
# * size -- integer column storing the size in bytes of the stored file data
# * total_chunks -- stores the calculated total of chunks the file
# * chunks_received -- a serialized text column maintaining an array of chunks recieved for the file
module FileStorage::Storable
  
  class FileValidationFailure < StandardError
  end
  
  class SizeMatchFailure < FileValidationFailure
    attr_accessor :expected_size, :calculated_size
    def initialize(expected_size, calculated_size)
      self.expected_size = expected_size
      self.calculated_size = calculated_size
    end
    def message
      "Sizes don't match, expected file to be #{expected_size} bytes. But concatenation of all recieved chunks is #{calculated_size} bytes"
    end
  end
  
  class HashMatchFailure < FileValidationFailure
    attr_accessor :expected_hash, :calculated_hash
    def initialize(expected_hash, calculated_hash)
      self.expected_hash = expected_hash
      self.calculated_hash = calculated_hash
    end
    def message
      "Hashes don't match after re-assembling the file, Expected file hash to be #{expected_hash} but calculated #{calculated_hash}"
    end
  end
  
  # On inclusion, checks that base class is an ActiveRecord model 
  # that implementes the required columns for a 'storable' object
  #
  # Also:
  # * setup 'chunks_received' columns to be serialized (will store an array of integers)
  # * setup validations to ensure that locator is set and that each instance has an attached entity
  # * setup after_save to ensure at least an empty file exists in the backend
  def self.included(base)
    columns_that_should_be_checked = ["locator", "file_hash_type", "file_hash",
        "size", "total_chunks", "chunks_received", "size_of_data_received", "lock_version"].each do |column_name|
      unless base.column_names.include?(column_name.to_s)
        raise ArgumentError, "#{base} expected to have a column for #{column_name}"
      end
    end
    
    base.class_eval do
      serialize :chunks_received
      serialize :metadata
      
      validates_presence_of :locator, :locate_attached_entity
      
      after_destroy do |thing|
        FileStorage.backend.delete_file(thing.locator) if thing.locator
      end
    end
  end
  
  def file_stream_proc
    FileStorage.backend.file_stream_proc(self.locator)
  end
  
  # Determine the first chunk that has not been received
  # chunks numbers start at 1 and end at total_chunks
  # if the file is completed, return nil
  def start_chunk
    return nil unless self.total_chunks
    self.chunks_received ||= []
    (1..self.total_chunks).each do |chunk_num|
      unless self.chunks_received.include?(chunk_num)
        return chunk_num
      end
    end
    return nil
  end
  
  # Determine if all of the file chunks have been received. (assuming the file is being transfered in chunks)
  def all_chunks_received?
    start_chunk == nil
  end
  
  def put_chunk(chunk_number, data)
    begin    
      put_chunk_unsafe(chunk_number, data)
    rescue ActiveRecord::StaleObjectError => e
      # STDERR.puts "stale object caught"
      self.reload
      retry
    end
  end
  
  # Write data for the given chunk number
  def put_chunk_unsafe(chunk_number, data)
    unless (1..self.total_chunks).member?(chunk_number)
      raise ArgumentError, "#{chunk_number} is not a valid chunk_number for this file"
    end
    if file_done?
      raise ArgumentError, "Can't put any chunks for this file because it is already completed"
    end
    self.chunks_received ||= []
    FileStorage.backend.put_chunk(self.locator, chunk_number, data)

    if self.chunks_received.include?(chunk_number)
      #If we have already received this chunk, DO put it in the backend, but DON'T record it again
    else
      #Note: Doing this so that active record 'dirty' notices a change to chunks_received: (instead of self.chunks_received << chunk_number)
      chunks_r = self.chunks_received.dup
      chunks_r << chunk_number
      self.chunks_received = chunks_r
      self.size_of_data_received ||= 0
      self.size_of_data_received += data.size
    end
    
    if(all_chunks_received?)
      begin
        FileStorage.backend.assemble_chunks_into_a_file(self.locator, (1..self.total_chunks), self.size)
        self.update_file_hash       
      rescue FileStorage::Storable::FileValidationFailure => e
        #If there was a size mismatch of a hash mismatch, then start over (chunks were deleted by 'assemble_chunks_into_a_file')
        self.chunks_received = []
        self.size_of_data_received = 0
        self.save!
        raise e
      rescue IOError => ioe
        #If there was a size mismatch of a hash mismatch, then start over (chunks were deleted by 'assemble_chunks_into_a_file')
        self.chunks_received = []
        self.size_of_data_received = 0
        self.save!
        raise ioe
      end
    end
    self.save!
  end
  
  def copy_from(another_storable)
    FileStorage.copy_file(another_storable.locator, self.locator, another_storable.size)
    self.file_hash = nil
    update_file_hash
    self.size_of_data_received = another_storable.size
  end
  
  def copy_from_url(backend_http_url, expected_size)
    FileStorage.copy_to_from_url(self.locator, backend_http_url, expected_size)
    self.file_hash = nil
    update_file_hash
    self.size_of_data_received = expected_size
  end
  
  def put_file_contents(data)
    FileStorage.put_file_contents(self.locator, data)
    self.file_hash = nil
    update_file_hash
    self.size_of_data_received = data.size
  end
  
  def get_file_contents
    FileStorage.get_file_contents(self.locator)
  end
  
  def get_forwardable_url
    FileStorage.get_forwardable_url(self.locator)    
  end

  # Check the size of data received against expected size to determine if the file is done
  def file_done?
    self.size && self.size_of_data_received == self.size
  end
  
  def percent_uploaded(size_received = self.size_of_data_received)
    self.size_of_data_received.to_i * 100 / self.size
  end  

  # Recalculate the file hash and store in meta data
  def update_file_hash
    self.file_hash_type = "sha1"
    new_hash = FileStorage.backend.file_hash(self.locator)
    unless self.file_hash.blank?
      if self.file_hash != new_hash
        raise HashMatchFailure.new(self.file_hash, new_hash)
      end
    end
    self.file_hash = new_hash
  end

  # Test is the hash we have in meta data matches the hash given
  def matches_hash?(hash_to_check)
    hash_to_check == self.file_hash
  end

  attr_accessor :attached_entity
  
  # Storable is just a table for storing standard meta data and file information
  # It is expected that further information about the stored file is available in an attached entity
  # in our test model Initech DMS
  # The Storable model is a ManagedDocument, and locate_attached_entity should find 
  # the TpsReport or TpsCoverSheet that corresponds to this ManagedDocument
  def locate_attached_entity
    #TODO: locator should be delimited with something that we can split("__?Sd028S") on, 
    # and it should be lowercase (we can camelize.contantize) from an underscore-ed string to continue to do what we're doing here...
    
    return self.attached_entity if self.attached_entity
    
    return nil unless locator
    
    klass, locator_id = FileStorage.split_locator(locator)
    
    if to_return = klass.send("find_by_#{self.class.name.underscore}_id", self.id)
      to_return.file_storage_via_assoc = self
    end
    to_return
  end
  
  
end
