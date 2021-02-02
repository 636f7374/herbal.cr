require "../src/herbal.cr"

# Durian

dns_servers = [] of Durian::Resolver::Server
dns_servers << Durian::Resolver::Server.new ipAddress: Socket::IPAddress.new("8.8.8.8", 53_i32), protocol: Durian::Protocol::UDP
dns_servers << Durian::Resolver::Server.new ipAddress: Socket::IPAddress.new("1.1.1.1", 53_i32), protocol: Durian::Protocol::UDP

dns_resolver = Durian::Resolver.new dns_servers
dns_resolver.ip_cache = Durian::Cache::IPAddress.new

# Herbal

begin
  client = Herbal::Client.new "0.0.0.0", 1234_i32, dns_resolver

  # Authentication (Optional)
  # client.authentication_methods = [Herbal::Authentication::NoAuthentication, Herbal::Authentication::UserNamePassword]
  # client.on_auth = Herbal::AuthenticationEntry.new "admin", "abc123"

  client.connect! "8.8.8.8", 53_i32, Herbal::Command::AssociateUDP, remote_resolution: true

  # Write Payload

  request = Durian::Packet.new Durian::Protocol::UDP, Durian::Packet::QRFlag::Query
  request.add_query "www.example.com", Durian::RecordFlag::A
  client.write request.to_slice

  # _Read Payload

  STDOUT.puts [Durian::Packet.from_io Durian::Protocol::UDP, client]

  request = Durian::Packet.new Durian::Protocol::UDP, Durian::Packet::QRFlag::Query
  request.add_query "www.google.com", Durian::RecordFlag::A
  client.write request.to_slice

  # _Read Payload

  STDOUT.puts [Durian::Packet.from_io Durian::Protocol::UDP, client]
rescue ex
  STDOUT.puts [ex]
end

client.try &.close
