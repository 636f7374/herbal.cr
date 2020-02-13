require "../src/tomato.cr"

def handle_client(context : Tomato::Context)
  STDOUT.puts context.summary

  context.perform
end

# Durian
servers = [] of Tuple(Socket::IPAddress, Durian::Protocol)
servers << Tuple.new Socket::IPAddress.new("8.8.8.8", 53_i32), Durian::Protocol::UDP
servers << Tuple.new Socket::IPAddress.new("1.1.1.1", 53_i32), Durian::Protocol::UDP
resolver = Durian::Resolver.new servers
resolver.ip_cache = Durian::Resolver::Cache::IPAddress.new

# Tomato
tcp_server = TCPServer.new "0.0.0.0", 1234_i32
tomato = Tomato::Server.new tcp_server, resolver
tomato.authentication = Tomato::Authentication::NoAuthentication
tomato.client_timeout = Tomato::TimeOut.new
tomato.remote_timeout = Tomato::TimeOut.new

# Authentication (Optional)
# server.authentication = Tomato::Authentication::UserNamePassword
# server.simple_auth = ->(user_name : String, password : String?) do
#  STDOUT.puts [user_name, password]
#  Tomato::Verify::Pass
# end

loop do
  while socket = tomato.accept?
    spawn do
      next unless client = socket
      next unless context = tomato.process client

      handle_client context
    end
  end
end
