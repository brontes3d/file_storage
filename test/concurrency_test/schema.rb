ActiveRecord::Schema.define do
  
  create_table "with_storage_things", :force => true do |t|
    t.integer  "storable_thing_id"    
  end

  create_table "storable_things", :force => true do |t|
    t.string   "locator"
    # t.string   "content_type"
    t.string   "file_name"
    # t.string   "mime_type"
    t.string   "file_hash_type"
    t.string   "file_hash"
    t.integer  "size"
    t.integer  "lock_version"
    t.integer  "size_of_data_received"
    t.integer  "total_chunks"
    t.datetime "created_at"
    t.datetime "updated_at"
    # t.text     "extended_attributes"
    t.text     "chunks_received"
  end

end