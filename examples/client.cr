require "../src/tomato.cr"

# Durian
servers = [] of Tuple(Socket::IPAddress, Durian::Protocol)
servers << Tuple.new Socket::IPAddress.new("8.8.8.8", 53_i32), Durian::Protocol::UDP
servers << Tuple.new Socket::IPAddress.new("1.1.1.1", 53_i32), Durian::Protocol::UDP
resolver = Durian::Resolver.new servers
resolver.ip_cache = Durian::Resolver::Cache::IPAddress.new

# Tomato
begin
  client = Tomato::Client.new "0.0.0.0", 1234_i32, resolver
  client.connect! "www.example.com", 80_i32, Tomato::Command::TCPConnection, true

  # Write Payload
  memory = IO::Memory.new
  request = HTTP::Request.new "GET", "http://www.example.com"
  request.to_io memory
  client.write memory.to_slice

  # _Read Payload
  buffer = uninitialized UInt8[4096_i32]
  length = client.read buffer.to_slice

  STDOUT.puts [:length, length]
  STDOUT.puts String.new buffer.to_slice[0_i32, length]
rescue ex
  STDOUT.puts [ex]
end

client.try &.close
