# FileStorage allows you to specify on your AR models:
#  
#    has_file_storage :data, :via => :managed_document
#
# This adds methods data and data= to the model for storing file data.
# In order to store meta data about the attached file, you need to specify a via parameter 
# which defines another AR model that is expect to include FileStorage::Storable
module FileStorage
    
  def self.backend
    if FILE_STORAGE_BACKEND == :file_system
      @@backend ||= FileStorage::Backend::FileSystem.new(FILE_STORAGE_PATH)        
    elsif FILE_STORAGE_BACKEND == :mogilefs
      @@backend ||= FileStorage::Backend::MogileFSStorage.new(FILE_STORAGE_MOGILEFS_CONFIG)
    elsif FILE_STORAGE_BACKEND == :in_memory
      @@backend ||= FileStorage::Backend::InMemory.new
    else
      raise "unknown FILE_STORAGE_BACKEND #{FILE_STORAGE_BACKEND.inspect}"
    end
    @@backend
  end
  
  def self.max_read_size
    if defined?(FILE_STORAGE_MAX_READ)
      FILE_STORAGE_MAX_READ
    else
      1048576
    end
  end
  
  def self.get_file_contents(locator)
    backend.get_file(locator)
  end
  
  def self.get_forwardable_url(locator)
    backend.get_forwardable_url(locator)    
  end
  
  def self.put_file_contents(locator, file_contents)
    backend.put_file(locator, file_contents)
  end
  
  def self.copy_file(from, to, data_size)
    backend.copy_file(from, to, data_size)    
  end
  
  def self.copy_to_from_url(to, from_url, data_size)
    backend.copy_to_from_url(to, from_url, data_size)
  end
  
  def self.generate_locator(for_klass, with_id)
    if with_id.index("_")
      raise ArgumentError, "locator id portions with _ in them are not allowed, given: #{with_id}"
    end
    "#{for_klass.name.underscore}_#{with_id}"
  end
  
  def self.split_locator(locator)
    splits = locator.split("_")
    klass_name = splits[0...-1].join("_")
    with_id = splits.last
    for_klass = klass_name.camelize.constantize
    [for_klass, with_id]
  end
  
  def self.log
    if defined?(Rails)
      Rails.logger || RAILS_DEFAULT_LOGGER
    else
      require 'facets/functor'
      Functor.new{ |method, arg| 
        # puts "#{method} -- #{arg}"
      }
    end
  end
      
end

