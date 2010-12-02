require 'mogilefs'
require 'rfuzz/client'

module FileStorage
  module Backend
    
    # A backend for the FileStorage plugin which utilizes MogileFS
    # from http://www.danga.com/mogilefs.
    #
    # *Warning*:: File IDs in MogileFS are case-insensitive.
    #--
    # a = MogileFS::Admin.new(:domain => "cm4_#{RAILS_ENV}", :hosts => ["lex-ea-cm4-int-0.mmm.com:6001"])
    # a = MogileFS::Admin.new(FILE_STORAGE_MOGILEFS_CONFIG)
    # a.each_fid { |fid| puts fid.inspect }
    # a.each_fid { |fid| mg.delete(fid['key']) }
    #
    # mg = MogileFS::MogileFS.new(:domain => "cm4_#{RAILS_ENV}", :hosts => %w[lex-ea-cm4-int-0.mmm.com:6001])
    # mg = MogileFS::MogileFS.new(FILE_STORAGE_MOGILEFS_CONFIG)
    # mg.list_keys('Case')[0].each { |f| mg.delete(f) }
    # 
    class MogileFSStorage < Base

      CHUNK_KEY_PREFIX = 'chunk'

      # create a MogileFS backend. +config+ should be a hash with these required keys:
      # :hosts:: an array of MogileFS tracker hosts and their port numbers.
      #          eg, <tt>%w[lex-ea-cm4-int-0.mmm.com:6001, lex-ea-cm4-int-1.mmm.com:6001]</tt>.
      # :domain:: the master domain for all files. eg, <tt>cm4_development_rajiv</tt>.
      # :file_class:: MogileFS class to use when storing files. eg, <tt>cm4_file</tt>.
      # :chunk_class:: MogileFS class to use when storing chunks of files, eg, <tt>cm4_chunk</tt>.
      def initialize(config) # trackers, domain
        @@config = config
        check_config
      end

      def status
        begin
          test_string = Time.now.to_f.to_s
          file_name = "MogileFSTest-#{Process.pid}-#{test_string}"
          put_file(file_name, test_string)
          raise "MogileFS test failed" unless get_file(file_name) == test_string
          delete_file(file_name)
        end
        "MogileFS backend OK"
      end
      
      def get_forwardable_url(file_id)
        paths_for(file_id).each do |path|
          next unless path
          case path
          when /^http:\/\// then
            # mogilefs backend is http
            return path
          else
            FileStorage.log.error "mogilefs backend skipping non-http path '#{path}'"            
          end
        end
        raise IOError, "no mogilefs paths returned data for key '#{file_id}'"        
      end
      
      def copy_file(from_id, to_id, data_size)
        from_url = get_forwardable_url(from_id)
        copy_to_from_url(to_id, from_url, data_size)
      end
      
      def put_file_from_write_proc(file_id, total_size, write_proc)
        raise IOError, "MogileFSStorage does not support 0 byte files." if total_size == 0

        klass = @@config[:file_class]
        klass = @@config[:chunk_class] if file_id.index(CHUNK_KEY_PREFIX) == 0
        
        FileStorage.log.info "storing #{total_size} bytes into mogilefs with key '#{file_id}'"
        mog_cmd :store_content, file_id, klass, (MogileFS::Util::StoreContent.new(total_size) do |write_callback|
          write_proc.call(write_callback)
        end)
        # ActsLikeAStringButRefersToAReadProc.new(read_proc, total_size)
        
        raise IOError, "'#{file_id}' does not exist in mogilefs after store_content" unless file_exists?(file_id)
        FileStorage.log.debug "storing #{total_size} bytes into mogilefs with key '#{file_id}' complete"        
      end
      
      def callback_to_write_proc(file_id, write_callback)
        path = get_forwardable_url(file_id)
        RFuzz::HttpClient.read_from_path_to_proc(path, write_callback)
      end
      
      def delete_file(file_id)
        FileStorage.log.info "deleting from mogilefs key '#{file_id}'"
        mog_cmd :delete, file_id
        FileStorage.log.debug "deleting from mogilefs key '#{file_id}' complete"
      end

      def rename_file(old_file_id, new_file_id)
        FileStorage.log.info "renaming mogilefs key '#{old_file_id}' to '#{new_file_id}'"
        raise IOError, "old key '#{old_file_id}' does not exist in mogilefs" unless file_exists?(old_file_id)
        mog_cmd :rename, old_file_id, new_file_id
        FileStorage.log.debug "renaming mogilefs key '#{old_file_id}' to '#{new_file_id}' complete"
      end
      
      # FIXME: we need to implement this for the mogilefs backend so the file data is not read on each file_size call
      # def file_size(file_id)
      # end

      # FIXME: we need to implement this for the mogilefs backend so the file data is not read on each file_hash call
      # def file_hash(file_id)
      # end

      def file_exists?(file_id)
        paths = mog_cmd :get_paths, file_id
        return false if paths.nil?
        # TODO: look at why paths could be an empty array. eg if there are no active paths to the files...
        if paths.empty?
          FileStorage.log.error "mogilefs returned empty paths array for key '#{file_id}'"
          return false
        end
        # TODO: should we check if the paths for the file exist?
        # TODO: should we check if the file is actually available?
        true
      end

      def chunk_id_for(file_id, chunk_number)
        [CHUNK_KEY_PREFIX, file_id, chunk_number].join('_')
      end
      
      private
      def check_config
        [:hosts, :domain, :file_class, :chunk_class].each do |option|
          unless @@config.include?(option)
            raise ArgumentError, "cannot initialize mogilefs backend. configuration option '#{option.to_s}' missing."
          end
        end
      end

      def mog_cmd(cmd, *args)
        should_retry = true
        begin
          mg = MogileFS::MogileFS.new(@@config)
          mg.send(cmd, *args)
        rescue MogileFS::UnreadableSocketError
          if should_retry
            FileStorage.log.error "mogilefs exception during '#{cmd}': #{$!.class.to_s}: #{$!.message.strip}"
            FileStorage.log.warn "attempting retry of mogilefs command '#{cmd}'"
            should_retry = false
            mg.backend.shutdown
            retry
          end
          raise
        end
      rescue
        FileStorage.log.fatal "mogilefs exception during '#{cmd}': #{$!.class.to_s}: #{$!.message.strip}\n#{(args || []).inspect}"
        raise IOError, "MogileFS backend FAIL, #{$!.class.to_s}: #{$!.message.strip}. #{cmd}:#{(args || []).inspect}"
      ensure
        mg.backend.shutdown
      end

      def paths_for(file_id)
        paths = mog_cmd :get_paths, file_id
        raise IOError, "no mogilefs paths available for key '#{file_id}'" unless paths
        FileStorage.log.debug "mogilefs paths for key '#{file_id}':"
        FileStorage.log.debug paths.inspect
        paths
      end

    end
  end
end
