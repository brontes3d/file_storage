$:.unshift "#{File.dirname(__FILE__)}/lib"
require 'file_storage'
require 'file_storage/storable'
require 'file_storage/act_methods'

require 'file_storage/bigger_pipe'

require 'mogilefs'

require 'rfuzz/client'
require 'file_storage/overrides/rfuzz_http_client'

require 'file_storage/backend/base'
require 'file_storage/backend/file_system'
require 'file_storage/backend/mogilefs_storage'
require 'file_storage/backend/in_memory'

ActiveRecord::Base.send(:extend, FileStorage::ActMethods)
