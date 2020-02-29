module Tomato
  class Client < IO
    getter dnsResolver : Durian::Resolver
    property wrapped : IO

    def initialize(@wrapped : IO, @dnsResolver : Durian::Resolver)
    end

    def self.new(host : String, port : Int32, dnsResolver : Durian::Resolver, connectTimeout : Int | Float? = nil)
      wrapped = Durian::TCPSocket.connect host, port, dnsResolver, connectTimeout

      new wrapped, dnsResolver
    end

    def self.new(ip_address : ::Socket::IPAddress, dnsResolver : Durian::Resolver, connectTimeout : Int | Float? = nil)
      wrapped = TCPSocket.connect ip_address, connectTimeout

      new wrapped, dnsResolver
    end

    def self.new(host : String, port : Int32, dnsResolver : Durian::Resolver, timeout : TimeOut = TimeOut.new)
      wrapped = Durian::TCPSocket.connect host, port, dnsResolver, timeout.connect
      wrapped.read_timeout = timeout.read
      wrapped.write_timeout = timeout.write

      new wrapped, dnsResolver
    end

    def self.new(ip_address : ::Socket::IPAddress, dnsResolver : Durian::Resolver, timeout : TimeOut = TimeOut.new)
      wrapped = TCPSocket.connect ip_address, connectTimeout, timeout.connect
      wrapped.read_timeout = timeout.read
      wrapped.write_timeout = timeout.write

      new wrapped, dnsResolver
    end

    def on_auth=(value : SimpleAuth)
      @onAuth = value
    end

    def on_auth
      @onAuth
    end

    def authentication_methods=(value : Array(Authentication))
      @authenticationMethods = value
    end

    def authentication_methods
      @authenticationMethods || [Authentication::NoAuthentication]
    end

    def version=(value : Version)
      @version = value
    end

    def version
      @version || Version::V5
    end

    def read(slice : Bytes) : Int32
      wrapped.read slice
    end

    def write(slice : Bytes) : Nil
      wrapped.write slice
    end

    def <<(value : String) : IO
      wrapped << value

      self
    end

    def flush
      wrapped.flush
    end

    def close
      wrapped.close
    end

    def closed?
      wrapped.closed?
    end

    def read_timeout=(value : Int | Float | Time::Span | Nil)
      _wrapped = wrapped

      _wrapped.read_timeout = value if value if _wrapped.responds_to? :read_timeout=
    end

    def write_timeout=(value : Int | Float | Time::Span | Nil)
      _wrapped = wrapped

      _wrapped.write_timeout = value if value if _wrapped.responds_to? :write_timeout=
    end

    def read_timeout
      _wrapped = wrapped
      _wrapped.read_timeout if _wrapped.responds_to? :read_timeout
    end

    def write_timeout
      _wrapped = wrapped
      _wrapped.write_timeout if _wrapped.responds_to? :write_timeout
    end

    def all_free
      _wrapped = wrapped
      _wrapped.all_free if _wrapped.responds_to? :all_free
    end

    def connect!(ip_address : ::Socket::IPAddress, command : Command, remote_resolution : Bool = false)
      connect! wrapped, ip_address.address, ip_address.port, command, false
    end

    def connect!(host : String, port : Int32, command : Command, remote_resolution : Bool = false)
      connect! wrapped, host, port, command, remote_resolution
    end

    def connect!(socket : IO, host : String, port : Int32, command : Command, remote_resolution : Bool = false)
      handshake socket
      auth_challenge socket

      case remote_resolution
      when true
        ip_address = Tomato.to_ip_address host, port

        case ip_address
        when ::Socket::IPAddress
          process socket, ip_address, command
        else
          process socket, host, port, command
        end
      when false
        method, ip_address = Durian::Resolver.getaddrinfo! host, port, dnsResolver
        process socket, ip_address, command
      end

      establish socket
    end

    private def handshake(socket : IO)
      raise UnknownFlag.new unless _version = version

      memory = IO::Memory.new
      memory.write Bytes[_version.to_i]

      optional = authentication_methods.size
      memory.write Bytes[optional.to_i]

      authentication_methods.each { |method| memory.write Bytes[method.to_i] }

      socket.write memory.to_slice
      socket.flush
    end

    private def auth_challenge(socket : IO)
      raise UnknownFlag.new unless _version = version
      raise MalformedPacket.new unless _get_version = Tomato.get_version socket
      raise MismatchFlag.new if _get_version != _version

      raise MalformedPacket.new unless _method = Tomato.get_authentication socket
      raise MalformedPacket.new unless authentication_methods.includes? _method

      memory = IO::Memory.new

      case _method
      when Authentication::UserNamePassword
        raise UnknownFlag.new unless auth = on_auth

        # 0x01 For Current version of UserName / Password Authentication
        # https://en.wikipedia.org/wiki/SOCKS

        memory.write Bytes[1_i32]
        memory.write Bytes[_version.to_i]

        memory.write Bytes[auth.userName.size]
        memory.write auth.userName.to_slice
        memory.write Bytes[auth.password.size]
        memory.write auth.password.to_slice

        socket.write memory.to_slice
        socket.flush

        raise MalformedPacket.new unless _get_version = Tomato.get_version socket
        raise MismatchFlag.new if _get_version != _version
        raise MalformedPacket.new unless verify = Tomato.get_verify socket
        raise AuthenticationFailed.new if verify.deny?
      end
    end

    private def process(socket, host : String, port : Int32, command : Command)
      raise UnknownFlag.new unless _version = version

      memory = IO::Memory.new
      memory.write Bytes[_version.to_i]
      memory.write Bytes[command.to_i]
      memory.write Bytes[Reserved::Nil.to_i]
      memory.write Bytes[Address::Domain.to_i]
      memory.write Bytes[host.size]

      memory.write host.to_slice
      memory.write_bytes port.to_u16, IO::ByteFormat::BigEndian

      socket.write memory.to_slice
      socket.flush
    end

    private def process(socket, ip_address, command : Command)
      raise UnknownFlag.new unless _version = version
      address_type = Tomato.to_address_type ip_address

      memory = IO::Memory.new
      memory.write Bytes[_version.to_i]
      memory.write Bytes[command.to_i]
      memory.write Bytes[Reserved::Nil.to_i]
      memory.write Bytes[address_type.to_i]

      case ip_address.family
      when .inet?
        memory.write Tomato.ipv4_address_to_bytes ip_address
      when .inet6?
        unless ipv6_address = Tomato.ipv6_address_to_bytes ip_address
          raise MalformedPacket.new "Invalid Ipv6 Address"
        end

        memory.write ipv6_address
      end

      memory.write_bytes ip_address.port.to_u16, IO::ByteFormat::BigEndian

      socket.write memory.to_slice
      socket.flush
    end

    private def establish(socket : IO)
      raise UnknownFlag.new unless _version = version
      raise MalformedPacket.new unless _get_version = Tomato.get_version socket
      raise MismatchFlag.new if _get_version != _version

      raise MalformedPacket.new unless _get_status = Tomato.get_status socket
      raise ConnectionDenied.new unless _get_status.indicates_success?
      raise MalformedPacket.new unless reserved = Tomato.get_reserved socket

      raise MalformedPacket.new unless address_type = Tomato.get_address socket
      raise MalformedPacket.new if address_type.domain?

      Tomato.extract_ip_address address_type, socket
    end
  end
end
