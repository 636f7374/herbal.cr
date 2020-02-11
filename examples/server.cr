require "../src/tomato.cr"

def handle_client(context : Tomato::Context)
  STDIN.puts context.summary

  context.perform
end

# Resolver
servers = [] of Tuple(Socket::IPAddress, Durian::Protocol)
servers << Tuple.new Socket::IPAddress.new("8.8.8.8", 53_i32), Durian::Protocol::UDP
servers << Tuple.new Socket::IPAddress.new("1.1.1.1", 53_i32), Durian::Protocol::UDP
resolver = Durian::Resolver.new servers
resolver.ip_cache = Durian::Resolver::Cache::IPAddress.new

# Tomato
server = Tomato::Server.new "0.0.0.0", 1234_i32
server.authentication = Tomato::Authentication::NoAuthentication
server.dns_resolver = resolver
server.client_timeout = Tomato::TimeOut.new
server.remote_timeout = Tomato::TimeOut.new

# Authentication (Optional)
# server.authentication = Tomato::Authentication::UserNamePassword
# server.simple_auth = ->(user_name : String, password : String?) do
#  STDIN.puts [user_name, password]
#  Tomato::Verify::Pass
# end

loop do
  while socket = server.accept?
    spawn do
      next unless client = socket
      next unless context = server.process client

      handle_client context
    end
  end
end
