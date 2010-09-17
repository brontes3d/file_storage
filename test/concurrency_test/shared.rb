#require this plugin
require "#{File.dirname(__FILE__)}/../../init"

FileStorage.class_eval do
  def self.backend
    @@backend ||= FileStorage::Backend::FileSystem.new(File.join(DIR_FOR_CONCURRENT_TEST, "concurrent_test"))
  end
end

class StorableThing < ActiveRecord::Base
  include FileStorage::Storable
  
end

class WithStorageThing < ActiveRecord::Base
  has_file_storage :data, :via => :storable_thing  
  
end