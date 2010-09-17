class BiggerPipe
  
  def protect_do
    @semaphore.synchronize {
      yield
    }
  end
    
  attr_accessor :available_to_read, :writer_done, :total_size_read, :total_size_write
  
  def initialize(tempfile)
    @semaphore = Mutex.new
    @tempfile = tempfile
    self.available_to_read = 0
    self.total_size_read = 0
    self.total_size_write = 0
    self.writer_done = false
  end
  
  class Reader
    def initialize(tempfile, biggerpiper)
      @tempfile = tempfile
      @biggerpiper = biggerpiper
    end
    
    def protect_do
      @biggerpiper.protect_do {
        yield
      }
    end
    
    def read(*args)
      if args.size == 0
        # if (!@biggerpiper.writer_done)
        #   puts "waiting for writer to finish"          
        # end
        while(protect_do{
          !(@biggerpiper.writer_done && @tempfile.size == @biggerpiper.total_size_write)
        }) do
          Thread.pass
        end
        to_return = @tempfile.read
        protect_do{
          @biggerpiper.available_to_read = 0          
        }
        to_return
      elsif(args.size == 1)
        bytes = args[0]
        # if(@biggerpiper.available_to_read < bytes)
        #   puts "waiting for writer to finish up to #{bytes}"
        # end
        while(protect_do{
         (@biggerpiper.available_to_read < bytes || @tempfile.size < (@biggerpiper.total_size_read + bytes)) && 
         !(@biggerpiper.writer_done && @tempfile.size == @biggerpiper.total_size_write)
        }) do
          Thread.pass
        end
        # puts "supposed to read #{bytes}"
        protect_do {
          @biggerpiper.available_to_read -= bytes
          @biggerpiper.total_size_read += bytes
        }
        @tempfile.read(bytes)
      else
        raise "Can't handle args #{args.inspect}"
      end
    end
    
    def close
      @tempfile.close
      @tempfile.delete
      
      # Rails.logger.debug("reader closed!")
      
    end
    
  end
  
  class Writter
    def protect_do
      @biggerpiper.protect_do {
        yield
      }
    end
    
    def initialize(tempfile, biggerpiper)
      @tempfile = File.open(tempfile.path, "w+")
      @biggerpiper = biggerpiper
    end
    
    def write(data_to_write)
      @tempfile.write(data_to_write)
      protect_do{
        @biggerpiper.available_to_read += data_to_write.size
        @biggerpiper.total_size_write += data_to_write.size
      }
    end
    
    def close
      @tempfile.close
      
      # Rails.logger.debug("writter closed!")
      
      protect_do{
        @biggerpiper.writer_done = true
      }
      # puts "Writter closed!"
    end
    
  end
  
  def self.pipe
    @tempfile = Tempfile.new("whatithoughtapipewas")
    
    # Rails.logger.debug("pipe created #{@tempfile.path}")
    
    biggerpiper = BiggerPipe.new(@tempfile)
    [Reader.new(@tempfile, biggerpiper), Writter.new(@tempfile, biggerpiper)]
  end
  
end