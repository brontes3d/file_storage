require 'mongrel'
class MockMogile
  attr_accessor :stored_data #(key to data)
  attr_accessor :fid_to_key
  attr_accessor :key_to_fid
  attr_accessor :tracker_port
  attr_accessor :storage_port
  
  cattr_accessor :running_mock
  def self.reset
    self.running_mock ||= MockMogile.new
    self.running_mock.stored_data = {}
    self.running_mock.fid_to_key = {}
    self.running_mock.key_to_fid = {}
  end
  
  def initialize
    @tracker_port = 4000
    @storage_port = 4001
    self.stored_data ||= {}
    self.fid_to_key ||= {}
    self.key_to_fid ||= {}
    @seed = 0
    
    begin
      @tracker = Tracker.new(self, @tracker_port, @storage_port)
      @storage = Storage.new(self, @storage_port)
    rescue Errno::EADDRINUSE => e
      @tracker_port += 2
      @storage_port = @tracker_port + 1
      retry
    end
    
    until(@tracker.ready && @storage.ready)
      Thread.pass
    end
  end
  def new_fid_for_key(key)
    @seed += 1
    self.key_to_fid[key] = @seed
    self.fid_to_key[@seed] = key
    # puts "key_to_fid: " + self.key_to_fid.inspect
    # puts "fid_to_key: " + self.fid_to_key.inspect
    @seed
  end
  def delete_key(key)
    fid = self.key_to_fid[key]
    self.key_to_fid.delete(key)
    self.fid_to_key.delete(fid)
    self.stored_data.delete(key)
  end
  
  class Tracker
    attr_accessor :ready
    def initialize(mocker, port, storage_port)
      self.ready = false
      @sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      @sock.bind(Socket.pack_sockaddr_in(port, '127.0.0.1'))
      @sock.listen(5)
      @thr = Thread.new do
        begin
          self.ready = true
          client, client_addr = @sock.accept
          client.sync = true
          
          loop do
            received = client.readline
            # puts "received #{received}"
            if received.start_with?("create_open")
              key = received.split("&").collect{ |s| /key=(.*)/.match(s) }.detect{|m| !m.nil?}[1]
              fid = mocker.new_fid_for_key(key)
              client.write("OK dev_count=1&path_1=http://127.0.0.1:#{storage_port}/dev203/0/000/404/0000#{fid}.fid&fid=#{fid}&devid_1=203\r\n")              
            end
            if received.start_with?("create_close")
              client.write("OK\r\n")
              client.close
              client, client_addr = @sock.accept
              client.sync = true          
            end
            if received.start_with?("delete")
              key = received.split("&").collect{ |s| /key=(.*)/.match(s) }.detect{|m| !m.nil?}[1]
              mocker.delete_key(key)
              client.write("OK\r\n")
              client.close
              client, client_addr = @sock.accept
              client.sync = true          
            end
            if received.start_with?("get_paths")
              key = received.split("&").collect{ |s| /key=(.*)/.match(s) }.detect{|m| !m.nil?}[1]
              fid = mocker.key_to_fid[key]
              if fid
                client.write("OK path1=http://127.0.0.1:#{storage_port}/dev203/0/000/404/0000#{fid}.fid&paths=1\r\n")
              else
                client.write("ERR unknown_key unknown_key\r\n")
              end
              client.close
              client, client_addr = @sock.accept
              client.sync = true
            end
          end
        rescue => e
          # STDERR.puts e.inspect + e.backtrace.join("\n")
        end
      end
    end
  end
  
  class Storage
    class StorageHandler < Mongrel::HttpHandler
      def initialize(mocker)
        @mocker = mocker
        super()
      end
      def process(request, response)
        #The test_read_write_limits test overrides TCPSocket and calls this method when a large read or write occurs
        #But since this is a socket in a mock, we don't care if there is a large read or write here... 
        #so override this method on just this instance of socket, so we don't care about testing mongrel's sockets
        response.socket.instance_eval do
          class << self
            def report_on_read_or_write(method, size)
            end
          end
        end        
        if request.params["REQUEST_METHOD"] == "GET"
          response.start(200) do |head,out|
            out.write(@mocker.stored_data[request.params["PATH_INFO"]])
          end
        elsif request.params["REQUEST_METHOD"] == "PUT"
          @mocker.stored_data[request.params["PATH_INFO"]] = request.body.read
          response.start(200) do |head,out|
            out.write("")
          end
        end
        #TODO: else: 404 not found
      end
    end    
    attr_accessor :ready
    def initialize(mocker, port)
      @server = Mongrel::HttpServer.new("127.0.0.1", port)
      @server.register("/", StorageHandler.new(mocker))
      @server.run
      self.ready = true
    end
  end

end
