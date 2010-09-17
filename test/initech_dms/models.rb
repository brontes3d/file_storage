class ManagedDocument < ActiveRecord::Base
  include FileStorage::Storable
  
end

#Memo's are small documents, so we won't be transfering them in chunks, 
#instead we'll just be setting :data right away on each
#There we are also going to add a validation to make sure data is set
class Memo < ActiveRecord::Base
  validates_presence_of :data
  has_file_storage :data, :locator => 'bills_report_number', :via => :managed_document, :write_on_save => true
  
end

#TPS reports are large documents, we will test with chunk-based transfer
class TpsReport < ActiveRecord::Base
  has_file_storage :data, :via => :managed_document, :alias_columns => ['file_name']
  
end

class TpsCoverSheet < ActiveRecord::Base
  validates_presence_of :test_number
  
  has_file_storage :data, :locator => 'test_number', :via => :managed_document
  
  
end