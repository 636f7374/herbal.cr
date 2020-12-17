<div align = "center"><img src="images/icon.png" width="256" height="256" /></div>

<div align = "center">
  <h1>Herbal.cr - SOCKS5 Client and Server</h1>
</div>

<p align="center">
  <a href="https://crystal-lang.org">
    <img src="https://img.shields.io/badge/built%20with-crystal-000000.svg" /></a>
  <a href="https://github.com/636f7374/herbal.cr/actions">
    <img src="https://github.com/636f7374/herbal.cr/workflows/Continuous%20Integration/badge.svg" /></a>
  <a href="https://github.com/636f7374/herbal.cr/releases">
    <img src="https://img.shields.io/github/release/636f7374/herbal.cr.svg" /></a>
  <a href="https://github.com/636f7374/herbal.cr/blob/master/license">
    <img src="https://img.shields.io/github/license/636f7374/herbal.cr.svg"></a>
</p>

## Description

* I saw some designs, But it is not ideal / meets the requirements.
  * [wontruefree / socks](https://github.com/wontruefree/socks)
  * [kostya / socks](https://github.com/kostya/socks)
* After a day of conception / thinking, a day of design / debugging, `Herbal.cr` has been initially completed.
  * I reference to [RFC1928](https://tools.ietf.org/html/rfc1928) and some guidelines for design, actually SOCKS5 is not difficult.
  * Third-party guides are more effective and practical, and has been verified by Wireshark test.
* Due to time constraints, Travis-CI and Spec tests have not been added for the time being.
* While designing, I drew [RFC1928](https://tools.ietf.org/html/rfc1928) as a drawing, That's why I did it quickly, (I put in the root directory).

## Features

* It can proxy TCP traffic as well as UDP traffic.
  * TCPConnection
  * TCPBinding
  * AssociateUDP
* It is a full-featured SOCKS5 Client / Server.
  * SimpleAuth (Does not support GSSAPI)
  * Local DNS resolution / Remote DNS resolution
  * TCPConnection / TCPBinding / AssociateUDP
  * Reject Establish (Server)
* Plugin (Fuzzy Wrapper)
  * HTTP / 1.1 KeepAlive Wrapper
  * WebSocket Wrapper
* Loosely coupled, Low footprint, High performance.
* ...

## Tips

* Does not support [Generic Security Services Application Program Interface](https://en.wikipedia.org/wiki/Generic_Security_Services_Application_Program_Interface) authentication.
* Does not support SOCKS4 and SOCKS4A Protocols.

## Usage

* Simple Client

```crystal
require "herbal"

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
```

* Simple Server

```crystal
require "herbal"

def handle_client(context : Herbal::Context)
  STDOUT.puts context.stats

  context.perform
end

# Durian

servers = [] of Durian::Resolver::Server
servers << Durian::Resolver::Server.new ipAddress: Socket::IPAddress.new("8.8.8.8", 53_i32), protocol: Durian::Protocol::TCP
servers << Durian::Resolver::Server.new ipAddress: Socket::IPAddress.new("1.1.1.1", 53_i32), protocol: Durian::Protocol::TCP

resolver = Durian::Resolver.new servers
resolver.ip_cache = Durian::Cache::IPAddress.new

# Herbal

tcp_server = TCPServer.new "0.0.0.0", 1234_i32
herbal = Herbal::Server.new tcp_server, resolver
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
```

```crystal
STDOUT.puts context.stats # => Herbal::Stats(@version=V5, @authenticationMethods=[NoAuthentication], @command=TCPConnection, @addressType=Domain, @remoteIpAddress=nil, @remoteAddress=#<Herbal::RemoteAddress:0x13f0a9340 @address="api.github.com", @port=443>)
```

### Used as Shard

Add this to your application's shard.yml:
```yaml
dependencies:
  herbal:
    github: 636f7374/herbal.cr
```

### Installation

```bash
$ git clone https://github.com/636f7374/herbal.cr.git
```

## Development

```bash
$ make test
```

## References

* [Official | Wikipedia - SOCKS](https://en.wikipedia.org/wiki/SOCKS)
* [Official | RFC 1928 - SOCKS Protocol Version 5 - IETF Tools](https://tools.ietf.org/html/rfc1928)
* [Document | How Socks 5 Works](https://samsclass.info/122/proj/how-socks5-works.html)
* [Document | SOCKS 5  - A Proxy Protocol](https://dev.to/nimit95/socks-5-a-proxy-protocol-5hcd)
* [Document | Implement SOCKS5 Protocol](https://developpaper.com/using-nodejs-to-implement-socks5-protocol/)


## Credit

* [\_Icon::Wanicon/Drink](https://www.flaticon.com/free-icon/herbal_1640397)
* [\_Icon::Freepik/Communication](https://www.flaticon.com/packs/communication-196)

## Contributors

|Name|Creator|Maintainer|Contributor|
|:---:|:---:|:---:|:---:|
|**[636f7374](https://github.com/636f7374)**|√|√||

## License

* GPLv3 License
