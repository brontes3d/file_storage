require 'rubygems'
require 'activerecord'
RAILS_ENV = 'test' unless defined?(RAILS_ENV)

#Args are...
DIR_FOR_CONCURRENT_TEST = ARGV[0]
storable_thing_id = ARGV[1]
chunk_interval = ARGV[2].to_i
chunk_out_of = ARGV[3].to_i
data_to_write = ARGV[4]

ActiveRecord::Base.configurations = YAML.load_file(File.dirname(__FILE__) + "/mysql_db.yml")
ActiveRecord::Base.establish_connection
load File.expand_path(File.dirname(__FILE__) + "/shared.rb")

storable_thing = StorableThing.find(storable_thing_id)

puts "going to write every #{chunk_interval} chunk in blocks of #{chunk_out_of} chunks for: #{storable_thing.inspect}"

write_chunk = chunk_interval
while(write_chunk <= storable_thing.total_chunks) do
  
  # STDERR.puts "write: #{write_chunk}"
  storable_thing.put_chunk(write_chunk, data_to_write)
  # STDERR.puts "storable_thing: " + storable_thing.inspect
  
  write_chunk += chunk_out_of
end

# STDERR.puts "in the end: " + storable_thing.file_done?.inspect

puts storable_thing.file_done?