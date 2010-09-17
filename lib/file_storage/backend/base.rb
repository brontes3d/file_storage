require 'tempfile'
module FileStorage
  module Backend

    class FileStorage::Backend::Timeout < Timeout::Error #:nodoc:
    end

    class Base
      require 'openssl'
      
      #subclasses expected to implement this method
      def status
        raise NotImplementedError.new("It is the responsibility of subclasses to implement the method 'status'")
      end
      
      #subclasses expected to implement this method
      def file_exists?(file_id)
        raise NotImplementedError.new("It is the responsibility of subclasses to implement the method 'file_exists?'")
      end
      
      #subclasses expected to implement this method
      def get_forwardable_url(file_id)
        raise NotImplementedError.new("#{self} does not support 'get_forwardable_url' (you need mogile fs backend for this feature)")
      end
      
      def copy_to_from_url(to_id, from_url, data_size)
        put_file_from_write_proc(to_id, data_size, Proc.new do |write_callback|
          RFuzz::HttpClient.read_from_path_to_proc(from_url, Proc.new do |to_write|
            write_callback.call(to_write)
          end)
        end)
      end
      
      def copy_file(from_id, to_id, data_size)
        put_file(to_id, get_file(from_id))
      end
      
      def put_file_from_read_proc(file_id, total_size, read_proc)
        put_file_from_write_proc(file_id, total_size, Proc.new do |write_callback|
          while to_write = read_proc.call
            write_callback.call(to_write)
          end
        end)
      end
      
      def put_file_from_write_proc(file_id, total_size, write_proc)
        raise NotImplementedError.new("It is the responsibility of subclasses to implement the method 'put_file_from_write_proc'")        
      end
      
      def put_file(file_id, data)
        FileStorage.log.info "Base is writing #{data.size} bytes to #{file_id}"
        
        if data.respond_to?(:read) or not data.is_a?(String)
          put_file_from_read_proc(file_id, data.size, Proc.new do
            data.read(FileStorage.max_read_size)
          end)
        else
          string_io = StringIO.new(data)
          put_file_from_read_proc(file_id, data.size, Proc.new do
            string_io.read(FileStorage.max_read_size)
          end)
        end
      end
      
      def get_file(file_id)
        result = StringIO.new
        callback_to_write_proc(file_id, Proc.new do |to_write|
          result.write(to_write)
        end)
        result.rewind
        
        FileStorage.log.info "get_file read #{result.size} bytes for #{file_id}"

        return result.read
      end
      
      def file_stream_proc(file_id)
        Proc.new do |translation_proc, output|
          # Rails.logger.debug("running file_stream_proc #{file_id}")
          # r, w = IO.pipe
          r, w = BiggerPipe.pipe
          
          # Rails.logger.debug("pipe created #{file_id}")
          exception_in_write = false
          buffer_thread = Thread.new do
            begin
              # Rails.logger.debug("buffer_thread running #{file_id}")
              buffer_write_proc(file_id).call(w)
            rescue => e
              FileStorage.log.error{ "Exception in write: #{e.inspect} " + e.backtrace.join("\n") }
              exception_in_write = e
            ensure
              w.close
            end
          end
          
          Thread.current[:cleanup_proc] = Proc.new do
            r.close
            if buffer_thread.alive?
              FileStorage.log.warn{ "killing alive buffer_thread ! #{buffer_thread.inspect} " }
            end
            buffer_thread.kill
          end
          
          # Rails.logger.debug("calling translation_proc #{file_id}")
          to_return = translation_proc.call(r, output)
          if Thread.current[:cleanup_proc]
            Thread.current[:cleanup_proc].call
            Thread.current[:cleanup_proc] = nil
          end
          
          if exception_in_write
            raise exception_in_write
          end
          # Rails.logger.debug("file_stream_proc returning #{file_id}")
          to_return
        end
      end
      
      def buffer_write_proc(file_id)
        Proc.new do |buffer|
          callback_to_write_proc(file_id, Proc.new do |to_write|
            buffer.write(to_write)
          end)
        end
      end
      
      #subclasses expected to implement this method
      def callback_to_write_proc(file_id, write_callback)
        raise NotImplementedError.new("It is the responsibility of subclasses to implement the method 'callback_to_write_proc'")        
      end
      
      #subclasses expected to implement this method
      def rename_file(old_file_id, new_file_id)
        raise NotImplementedError.new("It is the responsibility of subclasses to implement the method 'rename_file'")
      end

      #subclasses expected to implement this method
      def delete_file(file_id)
        raise NotImplementedError.new("It is the responsibility of subclasses to implement the method 'delete_file'")
      end
      
      #subclasses may choose to override this method with a more efficient implementation
      def file_size(file_id)
        # file_data = get_file(file_id)
        # if file_data
        #   file_data.size
        # else
        #   0
        # end
        FileStorage.log.info "Base backend getting file size for #{file_id}"
        running_total = 0
        callback_to_write_proc(file_id, Proc.new do |to_write|
          running_total += to_write.size
        end)
        running_total
      end
      
      #subclasses may choose to override this method with a more efficient implementation
      def file_hash(file_id)
        # OpenSSL::Digest::SHA1.new(get_file(file_id)).to_s
        FileStorage.log.info "Base backend getting file hash for #{file_id}"
        digest = OpenSSL::Digest::SHA1.new
        callback_to_write_proc(file_id, Proc.new do |to_write|
          digest << to_write
        end)
        digest.to_s
      end
      
      #subclasses may choose to override this method with a more efficient implementation
      #Responsible for deleting all chunks during concatenation
      #Responsible for deleting all chunks if there are any errors in assembly
      def assemble_chunks_into_a_file(file_id, range_of_chunks, expected_size)
        begin
          concatenation = Tempfile.new("stored-file-concat")
          range_of_chunks.each do |chunk_num|
            concatenation << get_chunk(file_id, chunk_num)
          end
          if concatenation.size != expected_size
            raise FileStorage::Storable::SizeMatchFailure.new(expected_size, concatenation.size)
          end
          concatenation.seek(0)
          put_file(file_id, concatenation)
          concatenation.close!
        ensure
          range_of_chunks.each do |chunk_num|
            begin
              delete_chunk(file_id, chunk_num)
            rescue
            end
          end
        end
      end
      
      #subclasses may choose to override this method
      def chunk_id_for(file_id, chunk_number)
        "#{file_id}_#{chunk_number}"
      end

      #subclasses may choose to override this method with a more efficient implementation
      def get_chunk(file_id, chunk_number)
        get_file(chunk_id_for(file_id, chunk_number))
      end
      
      #subclasses may choose to override this method with a more efficient implementation
      def put_chunk(file_id, chunk_number, data)
        put_file(chunk_id_for(file_id, chunk_number), data)
      end
      
      #subclasses may choose to override this method with a more efficient implementation
      def delete_chunk(file_id, chunk_number)
        delete_file(chunk_id_for(file_id, chunk_number))
      end
      
    end
  end
end
