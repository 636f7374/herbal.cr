module Tomato
  enum Authentication : UInt8
    NoAuthentication = 0_u8
    GSSAPI           = 1_u8
    UserNamePassword = 2_u8
  end

  enum Version : UInt8
    V5 = 5_u8
  end

  enum Address : UInt8
    Ipv4   = 1_u8
    Domain = 3_u8
    Ipv6   = 4_u8
  end

  enum Command : UInt8
    TCPConnection = 1_u8
    TCPBinding    = 2_u8
    AssociateUDP  = 3_u8
  end

  enum Status : UInt8
    IndicatesSuccess       = 0_u8
    ConnectFailed          = 1_u8
    ConnectionNotAllowed   = 2_u8
    NetworkUnreachable     = 3_u8
    HostUnreachable        = 4_u8
    ConnectionDenied       = 5_u8
    TTLTimeOut             = 6_u8
    UnsupportedCommand     = 7_u8
    UnsupportedAddressType = 8_u8
    Undefined              = 9_u8
  end

  enum Verify : UInt8
    Pass =   0_u8
    Deny = 255_u8
  end

  enum Reserved : UInt8
    Nil = 0_u8
  end

  class UnknownFlag < Exception
  end

  class MalformedPacket < Exception
  end

  class UnEstablish < Exception
  end

  class UnknownDNSResolver < Exception
  end

  class MismatchFlag < Exception
  end

  class AuthenticationFailed < Exception
  end

  class ConnectionDenied < Exception
  end

  class SimpleAuth
    property userName : String
    property password : String

    def initialize(@userName : String, @password : String)
    end
  end

  class TimeOut
    property read : Int32
    property write : Int32
    property connect : Int32

    def initialize(@read : Int32 = 30_i32, @write : Int32 = 30_i32, @connect : Int32 = 10_i32)
    end
  end

  class RemoteAddress
    property host : String
    property port : Int32

    def initialize(@host : String, @port : Int32)
    end
  end

  def self.empty_io : IO::Memory
    memory = IO::Memory.new 0_i32
    memory.close

    memory
  end

  def self.to_ip_address(host : String, port : Int32)
    ::Socket::IPAddress.new host, port rescue nil
  end

  def self.get_optional(io : IO) : Int32?
    buffer = uninitialized UInt8[1_i32]
    length = io.read buffer.to_slice rescue nil

    return unless _length = length
    return if _length.zero?

    optional = buffer.to_slice[0_i32]
    return if optional.zero?
    return if 3_u8 < optional

    optional.to_i32
  end

  def self.unspecified_ip_address
    ::Socket::IPAddress.new ::Socket::IPAddress::UNSPECIFIED, 0_i32
  end

  def self.to_address_type(ip_address : ::Socket::IPAddress)
    return Address::Ipv6 if ip_address.family.inet6?

    Address::Ipv4
  end

  def self.ipv4_address_to_bytes(ip_address : ::Socket::IPAddress) : Bytes
    buffer = IO::Memory.new 4_i32

    split = ip_address.address.split "."
    split.each { |part| buffer.write Bytes[part.to_u8] }

    buffer.to_slice
  end

  def self.ipv6_address_to_bytes(ip_address : ::Socket::IPAddress) : Bytes?
    return unless ip_address.family.inet6?

    pointer = ip_address.to_unsafe.as LibC::SockaddrIn6*
    memory = IO::Memory.new 16_i32

    {% if flag? :darwin %}
      ipv6_address = pointer.value.sin6_addr.__u6_addr.__u6_addr8
      memory.write ipv6_address.to_slice
    {% else %}
      ipv6_address = pointer.value.sin6_addr.__in6_u.__u6_addr8
      memory.write ipv6_address.to_slice
    {% end %}

    memory.to_slice
  end

  def self.decode_ipv6_address(io : IO) : String?
    buffer = IO::Memory.new 16_i32
    length = IO.copy io, buffer, 16_i32 rescue nil

    return unless _length = length
    return if _length.zero?
    return if 16_i32 != _length

    buffer.rewind
    ipv6_address = [] of String

    loop do
      first_byte = buffer.read_byte rescue nil
      _last_byte = buffer.read_byte rescue nil

      break unless first_byte
      break unless _last_byte

      first_hex = ("%02x" % first_byte).split String.new
      _last_hex = ("%02x" % _last_byte).split String.new

      case {first_hex.first, first_hex.last, _last_hex.first, _last_hex.last}
      when {"0", "0", "0", "0"}
        next if ipv6_address.empty?

        colon = ":" == ipv6_address.last && ":" == ipv6_address[-2_i32]?
        ipv6_address << ":" unless colon
      when {"0", "0", "0", _last_hex.last}
        ipv6_address << _last_hex.last << ":"
      when {"0", "0", _last_hex.first, _last_hex.last}
        ipv6_address << _last_hex.first
        ipv6_address << _last_hex.last << ":"
      when {"0", first_hex.last, _last_hex.first, _last_hex.last}
        ipv6_address << first_hex.last << _last_hex.first
        ipv6_address << _last_hex.last << ":"
      else
        ipv6_address << first_hex.first << first_hex.last
        ipv6_address << _last_hex.first << _last_hex.last << ":"
      end
    end

    return "::" if ipv6_address.empty?
    ipv6_address.pop if "::" == ipv6_address.last || ":" == ipv6_address.last

    address = ipv6_address.join
    return String.build { |io| io << "::" << address } if address.to_i?

    address
  end

  def self.extract_domain(io : IO) : RemoteAddress?
    buffer = uninitialized UInt8[1_i32]
    length = io.read buffer.to_slice rescue nil

    return unless length
    return if length.zero?

    length = buffer.to_slice[0_i32]
    memory = IO::Memory.new length
    length = IO.copy io, memory, length rescue nil

    return unless length
    return if length.zero?

    domain = String.new memory.to_slice
    port = io.read_bytes UInt16, IO::ByteFormat::BigEndian rescue nil
    return unless _port = port

    RemoteAddress.new domain, port.to_i32
  end

  def self.extract_ip_address(address_type : Address, io : IO) : ::Socket::IPAddress?
    case address_type
    when .ipv6?
      return unless ip_address = Tomato.decode_ipv6_address io

      port = io.read_bytes UInt16, IO::ByteFormat::BigEndian rescue nil
      return unless _port = port

      ::Socket::IPAddress.new ip_address, _port.to_i32 rescue nil
    when .ipv4?
      ipv4_buffer = uninitialized UInt8[4_i32]
      length = io.read ipv4_buffer.to_slice rescue nil
      return unless _length = length
      return if _length.zero? || 4_i32 != length

      ip_address = ipv4_buffer.to_slice.join "."

      port = io.read_bytes UInt16, IO::ByteFormat::BigEndian rescue nil
      return unless _port = port

      ::Socket::IPAddress.new ip_address, _port.to_i32 rescue nil
    end
  end

  {% for name in ["version", "command", "reserved", "address", "authentication", "verify", "status"] %}
  def self.get_{{name.id}}(io : IO) : {{name.capitalize.id}}?
    buffer = uninitialized UInt8[1_i32]
    length = io.read buffer.to_slice rescue nil

    return unless _length = length
    return if _length.zero?

    {{name.capitalize.id}}.from_value? buffer.to_slice[0_i32].to_i32
  end
  {% end %}

  {% for name in ["username", "password"] %}
  def self.get_{{name.id}}(io : IO) : String?
    buffer = uninitialized UInt8[1_i32]
    length = io.read buffer.to_slice rescue nil

    return unless _length = length
    return if _length.zero?

    {{name.id}}_length = buffer.to_slice[0_i32]
    return if {{name.id}}_length.zero?

    memory = IO::Memory.new {{name.id}}_length
    IO.copy io, memory, {{name.id}}_length rescue nil

    String.new memory.to_slice
  end
  {% end %}
end
