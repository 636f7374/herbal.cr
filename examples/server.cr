require "../src/herbal.cr"

def handle_client(context : Herbal::Context)
  STDOUT.puts [context.stats]

  context.perform
end

# Durian

dns_servers = [] of Durian::Resolver::Server
dns_servers << Durian::Resolver::Server.new ipAddress: Socket::IPAddress.new("8.8.8.8", 53_i32), protocol: Durian::Protocol::UDP
dns_servers << Durian::Resolver::Server.new ipAddress: Socket::IPAddress.new("1.1.1.1", 53_i32), protocol: Durian::Protocol::UDP

dns_resolver = Durian::Resolver.new dns_servers
dns_resolver.ip_cache = Durian::Cache::IPAddress.new

# Herbal

herbal = Herbal::Server.new "0.0.0.0", 1234_i32, dns_resolver
herbal.authentication = Herbal::Authentication::NoAuthentication
herbal.client_timeout = Herbal::TimeOut.new
herbal.remote_timeout = Herbal::TimeOut.new

# Authentication (Optional)
# herbal.authentication = Herbal::Authentication::UserNamePassword
# herbal.on_auth = ->(user_name : String, password : String?) do
#  STDOUT.puts [user_name, password]
#  Herbal::Verify::Pass
# end

loop do
  socket = herbal.accept?

  spawn do
    next unless client = socket
    next unless context = herbal.upgrade client

    handle_client context
  end
end
