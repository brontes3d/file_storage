ActiveRecord::Schema.define do

  create_table "tps_cover_sheets", :force => true do |t|
    t.integer  "managed_document_id"
    t.string   "product_code"
    t.string   "customer_code"
    t.integer   "vendor_number"
    t.integer   "test_number"
    t.integer   "number_of_errors"
    t.text      "summary"
  end

  create_table "memos", :force => true do |t|
    t.integer  "managed_document_id"
    t.string   "bills_report_number"
    t.string   "to"
    t.string   "from"
  end

  create_table "tps_reports", :force => true do |t|
    t.integer  "managed_document_id"
    t.string   "authors"
    t.integer  "tps_cover_sheet_id"
  end

  create_table "managed_documents", :force => true do |t|
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