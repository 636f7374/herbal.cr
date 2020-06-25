class Herbal::Socket < IO
  getter dnsResolver : Durian::Resolver
  property wrapped : IO

  def initialize(@wrapped : IO, @dnsResolver : Durian::Resolver)
  end

  def version=(value : Version)
    @version = value
  end

  def version
    @version
  end

  def authentication_methods=(value : Array(Authentication))
    @authenticationMethods = value
  end

  def authentication_methods
    @authenticationMethods
  end

  def authentication=(value : Authentication)
    @authentication = value
  end

  def authentication
    @authentication || Authentication::NoAuthentication
  end

  def on_auth=(value : Proc(String, String?, Herbal::Verify))
    @onAuth = value
  end

  def on_auth
    @onAuth
  end

  def command=(value : Command)
    @command = value
  end

  def command
    @command
  end

  def address_type=(value : Herbal::Address)
    @addressType = value
  end

  def address_type
    @addressType
  end

  def target_remote_ip_address=(value : ::Socket::IPAddress)
    @targetRemoteIpAddress = value
  end

  def target_remote_ip_address
    @targetRemoteIpAddress
  end

  def target_remote_address=(value : RemoteAddress)
    @targetRemoteAddress = value
  end

  def target_remote_address
    @targetRemoteAddress
  end

  def stats
    Stats.from_socket self
  end

  def loopback_unspecified? : Bool
    return false unless _target_remote_ip_address = target_remote_ip_address
    return true if _target_remote_ip_address.loopback? || _target_remote_ip_address.unspecified?

    false
  end

  def bad_remote_address?
    return false unless _target_remote_address = target_remote_address
    return true if loopback_unspecified? && _target_remote_address.port.zero?

    false
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

  def local_address : ::Socket::Address?
    _wrapped = wrapped

    if _wrapped.responds_to? :local_address
      local = _wrapped.local_address
      local if local.is_a? ::Socket::Address
    end
  end

  def remote_address : ::Socket::Address?
    _wrapped = wrapped

    if _wrapped.responds_to? :remote_address
      remote = _wrapped.remote_address
      remote if remote.is_a? ::Socket::Address
    end
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

  def auth_challenge! : Verify
    return Verify::Deny unless _version = version
    return Verify::Deny unless _methods = authentication_methods

    unless _methods.includes? authentication
      set_accept _version, Verify::Deny

      return Verify::Deny
    end

    # Set Authentication

    memory = IO::Memory.new
    memory.write Bytes[_version.to_i]
    memory.write Bytes[authentication.to_i]

    write memory.to_slice
    flush

    case authentication
    when Authentication::UserNamePassword
      # 0x01 For Current version of UserName / Password Authentication
      # https://en.wikipedia.org/wiki/SOCKS

      buffer = uninitialized UInt8[1_i32]
      length = read buffer.to_slice
      return Verify::Deny if length.zero?
      return Verify::Deny if 1_u8 != buffer.to_slice[0_i32]

      # Password / UserName

      return Verify::Deny unless username = Herbal.get_username! self
      password = Herbal.get_password! self

      # SimpleAuth Callback

      call = on_auth.try &.call username, password

      # 0x01 For Current version of UserName / Password Authentication
      # https://en.wikipedia.org/wiki/SOCKS

      write Bytes[1_i32]
      write Bytes[(call || Verify::Pass).to_i]
      flush

      return call || Verify::Pass
    end

    Verify::Pass
  end

  private def set_accept(version : Version, verify : Verify)
    write Bytes[version.to_i, verify.to_i]
    flush
  end

  def handshake! : Verify
    buffer = uninitialized UInt8[1_i32]

    # Version

    raise MalformedPacket.new unless _version = Herbal.get_version! self
    self.version = _version

    # Optional

    raise MalformedPacket.new unless optional = Herbal.get_optional! self

    # Methods

    authentication_methods = [] of Authentication

    optional.times do
      length = read buffer.to_slice
      raise MalformedPacket.new if length.zero?

      next unless value = Authentication.from_value? buffer.to_slice[0_i32].to_i32
      authentication_methods << value
    end

    raise MalformedPacket.new if authentication_methods.empty?
    self.authentication_methods = authentication_methods

    # Authentication

    auth_challenge!
  end

  def process!(sync_resolution : Bool = false)
    raise MalformedPacket.new unless version = Herbal.get_version! self
    raise MalformedPacket.new unless command = Herbal.get_command! self
    raise MalformedPacket.new unless reserved = Herbal.get_reserved! self
    raise MalformedPacket.new unless address = Herbal.get_address! self

    self.command = command
    self.address_type = address

    case address
    when .ipv6?
      ip_address = Herbal.extract_ip_address! address, self

      unless ip_address
        set_disconnect! version
        raise MalformedPacket.new
      end

      self.target_remote_address = RemoteAddress.new ip_address.address, ip_address.port
      self.target_remote_ip_address = ip_address
    when .ipv4?
      ip_address = Herbal.extract_ip_address! address, self

      unless ip_address
        set_disconnect! version
        raise MalformedPacket.new
      end

      self.target_remote_address = RemoteAddress.new ip_address.address, ip_address.port
      self.target_remote_ip_address = ip_address
    when .domain?
      target_remote_address = Herbal.extract_domain! self

      unless target_remote_address
        set_disconnect! version
        raise MalformedPacket.new
      end

      self.target_remote_address = target_remote_address
      return unless sync_resolution

      begin
        method, target_ip_address = Durian::Resolver.getaddrinfo! target_remote_address.host, target_remote_address.port, dnsResolver
      rescue ex
        set_disconnect! version
        raise ex
      end

      self.target_remote_ip_address = target_ip_address
    end
  end

  def establish!(sync_resolution : Bool = false)
    raise UnknownFlag.new unless _version = version
    raise UnknownFlag.new unless _address_type = address_type

    target_ip_address = target_remote_ip_address
    target_ip_address = Herbal.unspecified_ip_address if _address_type.domain? unless sync_resolution
    raise UnknownFlag.new unless target_ip_address

    memory = IO::Memory.new
    memory.write Bytes[_version.to_i]
    memory.write Bytes[Status::IndicatesSuccess.to_i]
    memory.write Bytes[Reserved::Nil.to_i]

    case _address_type
    when .ipv4?
      memory.write Bytes[_address_type.to_i]
      memory.write Herbal.ipv4_address_to_bytes target_ip_address
      memory.write_bytes target_ip_address.port.to_u16, IO::ByteFormat::BigEndian
    when .ipv6?
      unless ipv6_address = ::Socket::IPAddress.ipv6_to_bytes target_ip_address
        raise MalformedPacket.new "Invalid Ipv6 Address"
      end

      memory.write Bytes[_address_type.to_i]
      memory.write ipv6_address
      memory.write_bytes target_ip_address.port.to_u16, IO::ByteFormat::BigEndian
    when .domain?
      case target_ip_address.family
      when .inet?
        memory.write Bytes[Herbal::Address::Ipv4.to_i]
        memory.write Herbal.ipv4_address_to_bytes target_ip_address
      when .inet6?
        unless ipv6_address = ::Socket::IPAddress.ipv6_to_bytes target_ip_address
          raise MalformedPacket.new "Invalid Ipv6 Address"
        end

        memory.write Bytes[Herbal::Address::Ipv6.to_i]
        memory.write ipv6_address
      end

      memory.write_bytes target_ip_address.port.to_u16, IO::ByteFormat::BigEndian
    end

    write memory.to_slice
    flush
  end

  private def set_disconnect!(version : Version)
    write Bytes[version.to_i, Status::ConnectFailed.to_i]
    flush
  end
end

def reject_establish!
  raise UnknownFlag.new unless _version = version

  write Bytes[_version.to_i, Status::ConnectionDenied.to_i]
  flush
end
