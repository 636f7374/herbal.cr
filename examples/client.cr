require "../src/herbal.cr"

# Durian

servers = [] of Durian::Resolver::Server
servers << Durian::Resolver::Server.new ipAddress: Socket::IPAddress.new("8.8.8.8", 53_i32), protocol: Durian::Protocol::TCP
servers << Durian::Resolver::Server.new ipAddress: Socket::IPAddress.new("1.1.1.1", 53_i32), protocol: Durian::Protocol::TCP

resolver = Durian::Resolver.new servers
resolver.ip_cache = Durian::Cache::IPAddress.new

# Herbal

begin
  client = Herbal::Client.new "0.0.0.0", 1234_i32, resolver

  # Authentication (Optional)
  # client.authentication_methods = [Herbal::Authentication::NoAuthentication, Herbal::Authentication::UserNamePassword]
  # client.on_auth = Herbal::AuthenticationEntry.new "admin", "abc123"

  client.connect! "www.example.com", 80_i32, Herbal::Command::TCPConnection, true

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
