module FileStorage::ActMethods
  
  def has_file_storage(named, options = {:write_on_save => false})
    locator = options[:locator] || 'id'
    write_on_save = options[:write_on_save]
    
    # extra_columns_to_alias = [:content_type, :file_name, :mime_type]
    extra_columns_to_alias = options[:alias_columns] || []
    
    stored_file_model = options[:via]
    if stored_file_model.nil?
      raise ArgumentError, "You must provide :via in the options to specify the database model that will store the require attributes about the files stored"
    end
    stored_file_model_sym = stored_file_model.to_s.underscore.to_sym
    stored_file_model_constant = stored_file_model.to_s.camelize.constantize
    
    self.class_eval do
      def copy_data_from(another)
        self.transaction do
          self.incoming_chunked_file!(another.size, 1)
        end
        self.file_storage_via_assoc.copy_from(another.file_storage_via_assoc)
        self.transaction do
          self.file_storage_via_assoc.save!
          self.save!
        end
      end
      def copy_data_from_url(from_url, data_size)
        self.transaction do
          self.incoming_chunked_file!(data_size, 1)
        end
        self.file_storage_via_assoc.copy_from_url(from_url, data_size)
        self.transaction do
          self.file_storage_via_assoc.save!
          self.save!
        end        
      end
      
      # belongs_to :stored_file
      belongs_to stored_file_model_sym
      define_method('file_storage_via_assoc') do
        # self.send(stored_file_model_sym)
        if to_return = self.send(stored_file_model_sym)
          to_return.attached_entity = self
          to_return
        else
          self.file_storage_via_assoc = stored_file_model_constant.new
          self.file_storage_via_assoc.attached_entity = self
          self.file_storage_via_assoc
        end
      end
      define_method("file_storage_via_assoc=") do |arg|
        self.send(stored_file_model_sym.to_s + "=", arg)
      end
      
      after_destroy do |thing|
        thing.file_storage_via_assoc.destroy if thing.file_storage_via_assoc
      end
      
      #TODO: clearly there is no test for this part
      ([:file_hash_type, :file_hash, :size, :size_of_data_received, :metadata] + extra_columns_to_alias).each do |meth|
        define_method(meth) do
          self.file_storage_via_assoc.send(meth)
        end
        define_method("#{meth}=") do |arg|
          self.file_storage_via_assoc.send("#{meth}=", arg)
        end
      end
      def file_done?
        self.file_storage_via_assoc && self.file_storage_via_assoc.file_done?
      end
      def percent_uploaded
        return 0 unless self.file_storage_via_assoc
        self.file_storage_via_assoc.percent_uploaded
      end
      
      define_method('generate_stored_file_locator') do
        locator_ident_part = self.send(locator.to_sym).to_s
        if locator_ident_part.blank?
          raise ArgumentError, "calling #{locator} on #{self} returned blank, "+
          "So we can't use that as the locator. Define a different locator, or populate #{locator} "+
          "before attempting to attach a file."
        end
        ident = FileStorage.generate_locator(self.class, locator_ident_part)
      end
      
      #some semblance of test exists for this part...
      # define_method('incoming_chunked_file!') do |file_size|
      #   self.incoming_chunked_file(file_size)
      #   self.file_storage_via_assoc.save!
      #   self.save!
      #   self.file_storage_via_assoc
      # end
      # define_method('incoming_chunked_file') do |file_size|
      #   if self.file_storage_via_assoc.new_record?
      #     self.file_storage_via_assoc.locator = generate_stored_file_locator
      #     self.file_storage_via_assoc.chunks_received = []
      #     self.file_storage_via_assoc.size = file_size
      #     self.file_storage_via_assoc.total_chunks = ((self.file_storage_via_assoc.size+0.0) / CHUNK_SIZE).ceil
      #     # self.file_storage_via_assoc.save_without_validation!
      #     # self.save_without_validation!
      #   end
      #   self.file_storage_via_assoc
      # end
      def incoming_chunked_file!(file_size, custom_num_of_chunks = false)
        self.incoming_chunked_file(file_size, custom_num_of_chunks)
        self.file_storage_via_assoc.save!
        self.save!
        self.file_storage_via_assoc
      end
      def incoming_chunked_file(file_size, custom_num_of_chunks = false)
        if self.file_storage_via_assoc.new_record? || self.file_storage_via_assoc.locator.blank?
          self.file_storage_via_assoc.locator = generate_stored_file_locator
          self.file_storage_via_assoc.chunks_received = []
          self.file_storage_via_assoc.size = file_size
          if custom_num_of_chunks
            self.file_storage_via_assoc.total_chunks = custom_num_of_chunks
          else
            self.file_storage_via_assoc.total_chunks = ((self.file_storage_via_assoc.size+0.0) / CHUNK_SIZE).ceil
          end
          # self.file_storage_via_assoc.save_without_validation!
          # self.save_without_validation!
        end
        self.file_storage_via_assoc
      end

      after_save :write_to_disk
      define_method('write_to_disk') do
        
        #since self belongs to stored file, we need to save stored_file
        #before we can save self (so that self.stored_file_id is populated).
        #however, if stored_file already exists, we need only save the file 
        #contents and the stored_file object (as self.stored_file_id is already correct)
        if @stored_data && @something_new_to_save
          unless self.file_storage_via_assoc && self.file_storage_via_assoc.locator
            self.file_storage_via_assoc.locator ||= generate_stored_file_locator
            self.file_storage_via_assoc.size = @stored_data.size if @stored_data
            self.file_storage_via_assoc.put_file_contents(@stored_data)
            @something_new_to_save = false
            self.file_storage_via_assoc.save!
            self.save!
          else
            self.file_storage_via_assoc.size = @stored_data.size if @stored_data
            self.file_storage_via_assoc.put_file_contents(@stored_data)
            self.file_storage_via_assoc.save!
          end
        end
      end
      
      #When write_on_save is set to true in options
      #we write the contents of the stored_file to file_storage on save.
      #if write_on_save is false
      #we write the contents immediately on calls to the setter method.
      if write_on_save
        define_method(named.to_s) do
          unless @stored_data 
            return nil unless self.file_storage_via_assoc
            @stored_data = (self.file_storage_via_assoc.file_done?) ? self.file_storage_via_assoc.get_file_contents : nil
          end
          @stored_data
        end
        define_method(named.to_s+"=") do |arg|
          @something_new_to_save = true
          @stored_data = arg
        end
      else
        define_method(named.to_s) do
          return nil unless self.file_storage_via_assoc
          @stored_data ||= (self.file_storage_via_assoc.file_done?) ? self.file_storage_via_assoc.get_file_contents : nil
        end
        define_method(named.to_s+"=") do |arg|
          if self.new_record?
            @something_new_to_save = true
            @stored_data = arg
          else
            self.file_storage_via_assoc.locator ||= generate_stored_file_locator
            self.file_storage_via_assoc.size = arg.size if arg
            self.file_storage_via_assoc.put_file_contents(arg)
            self.file_storage_via_assoc.save!
          end
        end
      end
    end
  end
  
end
