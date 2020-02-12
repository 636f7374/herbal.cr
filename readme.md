<div align = "center"><img src="images/icon.png" width="256" height="256" /></div>

<div align = "center">
  <h1>Tomato.cr - SOCKS5 Client with Server</h1>
</div>

<p align="center">
  <a href="https://crystal-lang.org">
    <img src="https://img.shields.io/badge/built%20with-crystal-000000.svg" /></a>
  <a href="https://travis-ci.org/636f7374/tomato.cr">
    <img src="https://api.travis-ci.org/636f7374/tomato.cr.svg" /></a>
  <a href="https://github.com/636f7374/tomato.cr/releases">
    <img src="https://img.shields.io/github/release/636f7374/tomato.cr.svg" /></a>
  <a href="https://github.com/636f7374/tomato.cr/blob/master/license">
    <img src="https://img.shields.io/github/license/636f7374/tomato.cr.svg"></a>
</p>

## Description

* I saw the design of `wontruefree` and `kostya`, But it is not ideal / meets the requirements.
  * [wontruefree / socks](https://github.com/wontruefree/socks)
  * [kostya / socks](https://github.com/kostya/socks)
* After a day of conception / thinking, a day of design / debugging, `Tomato.cr` has been initially completed.
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
* Loosely coupled, Low footprint, High performance.
* ...

## Tips

* Does not support [Generic Security Services Application Program Interface](https://en.wikipedia.org/wiki/Generic_Security_Services_Application_Program_Interface) authentication.
* Does not support SOCKS4 and SOCKS4A Protocols.
* Why is it named `Tomato.cr`? it's just random six-word English words.

## Usage

* Simple Client

```crystal
require "tomato"

# Durian
servers = [] of Tuple(Socket::IPAddress, Durian::Protocol)
servers << Tuple.new Socket::IPAddress.new("8.8.8.8", 53_i32), Durian::Protocol::UDP
servers << Tuple.new Socket::IPAddress.new("1.1.1.1", 53_i32), Durian::Protocol::UDP
resolver = Durian::Resolver.new servers
resolver.ip_cache = Durian::Resolver::Cache::IPAddress.new

# Tomato
client = Tomato::Client.new resolver
client.create_remote "0.0.0.0", 1234_i32

begin
  client.connect! "www.example.com", 80_i32, Tomato::Command::TCPConnection, true
  request = HTTP::Request.new "GET", "http://www.example.com"
  request.to_io client

  buffer = uninitialized UInt8[4096_i32]
  length = client.read buffer.to_slice

  puts [:length, length]
  puts String.new buffer.to_slice[0_i32, length]
rescue ex
  puts [ex]
end

client.close
```

* Simple Server

```crystal
require "tomato"

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
tomato = Tomato::Server.new TCPServer.new "0.0.0.0", 1234_i32
tomato.authentication = Tomato::Authentication::NoAuthentication
tomato.dns_resolver = resolver
tomato.client_timeout = Tomato::TimeOut.new
tomato.remote_timeout = Tomato::TimeOut.new

# Authentication (Optional)
# server.authentication = Tomato::Authentication::UserNamePassword
# server.simple_auth = ->(user_name : String, password : String?) do
#  STDIN.puts [user_name, password]
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
```

```crystal
STDIN.puts context.summary # => [V5, [NoAuthentication, UserNamePassword], TCPConnection, Domain, Socket::IPAddress(203.208.41.68:443), #<Tomato::Domain:0x10ca12900 @domain="safebrowsing.googleapis.com", @port=443>]
```

### Used as Shard

Add this to your application's shard.yml:
```yaml
dependencies:
  tomato:
    github: 636f7374/tomato.cr
```

### Installation

```bash
$ git clone https://github.com/636f7374/tomato.cr.git
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

* [\_Icon::wanicon/fruits](https://www.flaticon.com/packs/fruits-and-vegetables-48)

## Contributors

|Name|Creator|Maintainer|Contributor|
|:---:|:---:|:---:|:---:|
|**[636f7374](https://github.com/636f7374)**|√|√||

## License

* GPLv3 License
