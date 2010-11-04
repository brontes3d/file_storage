RFuzz::HttpClient.class_eval do
  
  def self.read_from_path_to_proc(path, proc_callback)
    uri = URI.parse path
    FileStorage.log.info "reading from mogilefs '#{path}'"
    cl = RFuzz::HttpClient.new(uri.host, uri.port)
    
    cl.write_to_this_proc = Proc.new do |to_write|
      proc_callback.call(to_write)
    end
    
    begin
      resp = cl.send_request(:GET, uri.path, {})
    rescue IOError => e
      raise IOError, "Error reading from '#{path}': #{e.message}"
    end
    
    unless resp.http_status == "200"
      raise IOError, "mogilefs backend request to GET '#{path}' failed with '#{resp.http_status}'"
    end
    
    FileStorage.log.debug "reading from mogilefs '#{path}' complete"
  end
  
  attr_accessor :write_to_this_proc
  
  def read_response
    resp = RFuzz::HttpResponse.new

    notify :read_header do
      resp = read_parsed_header
    end

    notify :read_body do
      if resp.chunked_encoding?
        raise ArgumentError, "(FileStorage Plugin) Rfuzz Overrides does not support handling responses with chunked encoding"
      elsif resp[RFuzz::HttpClient::CONTENT_LENGTH]
        content_length = resp[RFuzz::HttpClient::CONTENT_LENGTH].to_i
        body_length = resp.http_body.length
        needs = content_length - body_length
        
        #Not doing this
          # Some requests can actually give a content length, and then not have content
          # so we ignore HttpClientError exceptions and pray that's good enough        
          # resp.http_body += @sock.read(needs) if needs > 0 rescue RFuzz::HttpClientError
        #Doing this instead
        if(resp.http_body.length > 0)
          self.write_to_this_proc.call(resp.http_body)
        end
        total_read_so_far = 0
        left_to_read = needs
        while(left_to_read > 0)
          amount_to_read = if left_to_read < FileStorage.max_read_size
            left_to_read
          else
            FileStorage.max_read_size
          end
          before_read = Time.now
          before_write = Time.now
          after_write = Time.now
          all_time_diffs ||= []
          begin
            if @last_read_completed
              all_time_diffs << "time size last read completed #{Time.now - @last_read_completed}"
            end
            if @last_read_began
              all_time_diffs << "time size last read began #{Time.now - @last_read_began}"
            end            
            before_read = Time.now
            @last_read_began = Time.now
            next_data_read = @sock.read(amount_to_read)
            @last_read_completed = Time.now
            before_write = Time.now
            self.write_to_this_proc.call(next_data_read)
            after_write = Time.now
            @last_time_diff = "#{before_write - before_read} to #{after_write - before_write} (#{Time.now - before_read})"
            # puts " so far #{needs - left_to_read}. still need #{left_to_read}. Expect block of #{amount_to_read}. total size #{needs}."
            # puts "time diff on write #{after_write - before_write}"
            left_to_read -= amount_to_read
          rescue RFuzz::HttpClientError => e
            raise IOError, "Mogile Not Responding? Total read so far #{needs - left_to_read}. still need to read #{left_to_read}. " +
                           "Expecting to read a block of #{amount_to_read}. total size to read #{needs}. " +
                           "content_length #{content_length}. body length #{body_length}. "+
                           "response: #{resp.inspect} " +
                           "\n last time diff: #{@last_time_diff}" +
                           "\n time diff: (#{before_write - before_read} to #{after_write - before_write}) (#{Time.now - before_read})" +
                           "\n all time diffs: #{all_time_diffs.join("\n")}"+
                           "\n(#{e.backtrace.join("\n")})"
          # ensure
            # FileStorage.log.debug{ "Rfuzz read completed #{amount_to_read}, left_to_read: #{left_to_read}, needs: #{needs}" }
          end
        end
        
      else
        raise ArgumentError, "(FileStorage Plugin) Rfuzz Overrides does not support handling responses that don't provide a CONTENT_LENGTH header"
      end
    end

    store_cookies(resp)
    return resp
  end

end
