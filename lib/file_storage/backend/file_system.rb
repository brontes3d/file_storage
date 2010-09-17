require 'fileutils'

module FileStorage
  module Backend
    class FileSystem < Base
      # include Logging
      
      attr_reader :base_path
      
      def status
        begin
          test_string = Time.now.to_f.to_s
          file_name = "FileSystemTest-#{Process.pid}-#{test_string}"
          put_file(file_name, test_string)

          file_path = path_for_file(file_name)
          raise "FileSystem test file missing" unless File.exists?(file_path)
          File.open(file_path, "r+") do |f|
            raise "FileSystem test failed" unless f.read == test_string
          end

          delete_file(file_name)
        rescue
          raise IOError, $!.message
        end
        'File System backend OK'
      end
      
      def rename_file(old_file_id, new_file_id)
        old_path = FileStorage.backend.path_for_file(old_file_id)
        new_path = FileStorage.backend.path_for_file(new_file_id)
        # FileUtils.mv(old_path, new_path)
        File.rename(old_path, new_path)
      end
            
      #TODO: implement a delete, ensure that if we are replacing a file, you delete before puttinh
      
      #TODO: define exceptions that could be thrown for the various operations            
      def file_exists?(file_id)
        File.exists?(path_for_file(file_id))
      end
      
      def put_file_from_write_proc(file_id, total_size, write_proc)
        FileStorage.log.info "File System backend is writing #{total_size} bytes to #{file_id}"
        File.open(path_for_file(file_id), "w+") do |file| 
          write_proc.call(Proc.new do |to_write|
            file.write(to_write)
          end)
        end
      end
            
      def put_file(file_id, data)
        if data.is_a?(String)
          FileStorage.log.info "File System backend writing #{data.size} bytes to #{file_id}"          
          File.open(path_for_file(file_id), "w+") do |file| 
            file.write(data)
          end
        else
          super(file_id, data)
        end
      end
      
      def copy_file(from_id, to_id, data_size)
        from_path = path_for_file(from_id)
        to_path = path_for_file(to_id)        
        FileUtils.cp(from_path, to_path)
      end
      
      # If we wanted to make file system backend for efficient, we would do this
      # But we'll stick with the base implementation so that we excersice just a little more of this code when running test/dev
      # and hope that it finds more bugs than the time it would save to be implemented in file system backend
      # def get_file(file_id)
      #   file_path = path_for_file(file_id)
      #   if(File.exists?(file_path))
      #     File.open(file_path, "r+") do |file| 
      #       file.read
      #     end
      #   end
      # end
      
      def callback_to_write_proc(file_id, write_callback)
        file_path = path_for_file(file_id)
        unless(File.exists?(file_path))
          raise IOError, "file doesn't exist in file system backend for file_id '#{file_id}'"          
        end
        FileStorage.log.info("reading file #{file_path} from file system backend")
        File.open(file_path, 'rb') do |input_file|
          while to_write = input_file.read(FileStorage.max_read_size)
            write_callback.call(to_write)
          end
        end
      end
      
      def file_size(file_id)
        # puts "asked for file size of #{file_id}"
        file_path = path_for_file(file_id)
        File.size(file_path)
      end

      def delete_file(file_id)
        file_path = path_for_file(file_id)
        if(File.exists?(file_path))
          File.delete(file_path)
        end
      end
      
      # TODO: write a test and uncomment this
      # def file_size(file_id)
      #   File.size(path_for_file(file_id))
      # end

      #this method is internal/specific to the implementation of FileSystem backend
      # TODO: well we can't exactly make private
      def initialize(path)
        # logger.debug("using file storage path: " + path.inspect)
        @base_path = path
        FileUtils.mkdir_p(@base_path)
      end

      #this method is internal/specific to the implementation of FileSystem backend, TODO: make private
      def path_for_file(file_id)
        path = File.join(@base_path, file_id.to_s)        
        # puts "path for file: #{file_id} is #{path}"
        return path
      end
          
    end
  end
end
