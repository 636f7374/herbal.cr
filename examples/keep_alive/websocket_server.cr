require "../../src/herbal.cr"

def handle_client!(server : Herbal::Server, client : Herbal::Socket)
  unless context = server.upgrade client
    client.close rescue nil

    raise "Upgrade Failed"
  end

  context.perform
end

def listen(server : Herbal::Server)
  loop do
    socket = server.accept?

    spawn do
      next unless client = socket
      accepted = HTTP::WebSocket.accept client.wrapped rescue false
      next unless accepted

      protocol = HTTP::WebSocket::Protocol.new client.wrapped
      stream = Herbal::Plugin::WebSocket::Stream.new protocol, option: client.option
      client.wrapped = stream

      # First time Process

      handle_client! server, client rescue next

      # KeepAlive Process

      loop do
        break if client.closed?
        break unless client.option.try &.allowKeepAlive
        next sleep 0.25_f32 if client.active?
        break unless client.keep_alive?

        handle_client! server, client rescue break
      end
    end
  end
end

# Durian

dns_servers = [] of Durian::Resolver::Server
dns_servers << Durian::Resolver::Server.new Socket::IPAddress.new("1.1.1.1", 53_i32), Durian::Protocol::UDP
dns_servers << Durian::Resolver::Server.new Socket::IPAddress.new("1.0.0.1", 53_i32), Durian::Protocol::UDP
dns_servers << Durian::Resolver::Server.new Socket::IPAddress.new("8.8.8.8", 53_i32), Durian::Protocol::UDP
dns_servers << Durian::Resolver::Server.new Socket::IPAddress.new("8.8.4.4", 53_i32), Durian::Protocol::UDP

dns_resolver = Durian::Resolver.new dns_servers
dns_resolver.ip_cache = Durian::Cache::IPAddress.new

# Herbal

option = Herbal::Option.new
option.allowKeepAlive = true

server = Herbal::Server.new "0.0.0.0", 1234_i32, dns_resolver, option
server.authentication = Herbal::Authentication::NoAuthentication

# Verify

# server.authentication = Herbal::Authentication::UserNamePassword
# server.on_auth = ->(user_name : String, password : String?) do
#  return Herbal::Verify::Deny if ("user" != user_name) || ("test" != password)
#
#  Herbal::Verify::Pass
# end

# TimeOut

client_timeout = Herbal::TimeOut.new
client_timeout.connect = 30_i32
client_timeout.read = 60_i32
client_timeout.write = 60_i32
server.client_timeout = client_timeout

remote_timeout = Herbal::TimeOut.new
remote_timeout.connect = 30_i32
remote_timeout.read = 60_i32
remote_timeout.write = 60_i32
server.remote_timeout = remote_timeout

listen server
