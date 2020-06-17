class Herbal::Context
  getter client : Socket
  getter dnsResolver : Durian::Resolver
  property timeout : TimeOut
  property clientEstablish : Bool
  property remote : IO

  def initialize(@client : Socket, @dnsResolver : Durian::Resolver, @timeout : TimeOut = TimeOut.new)
    @clientEstablish = false
    @remote = Herbal.empty_io
  end

  def remote=(value : IO)
    @remote = value
  end

  def remote
    @remote
  end

  def stats
    Stats.from_socket client
  end

  def connect_remote!
    return unless remote.is_a? IO::Memory if remote
    raise UnknownFlag.new unless command = client.command
    raise UnEstablish.new unless clientEstablish
    raise UnknownFlag.new unless target_remote_address = client.target_remote_address

    host = target_remote_address.host
    port = target_remote_address.port

    case command
    when .tcp_connection?
      remote = Durian::TCPSocket.connect host, port, dnsResolver, timeout.connect
    when .tcp_binding?
      remote = Durian::TCPSocket.connect host, port, dnsResolver, timeout.connect
      remote.reuse_address = true
      remote.reuse_port = true
      remote.bind remote.local_address
    when .associate_udp?
      remote = Durian::Resolver.get_udp_socket! host, port, dnsResolver
    end

    self.remote = remote if remote
    remote.try &.read_timeout = timeout.read
    remote.try &.write_timeout = timeout.write

    remote
  end

  def all_close
    client.close rescue nil
    remote.close rescue nil
  end

  def transport
    _transport = Transport.new client, remote
    _transport.perform
  end

  def perform
    begin
      connect_remote!
    rescue ex
      return all_close
    end

    transport
  end

  def client_establish
    client_establish rescue nil
  end

  def reject_establish
    reject_establish rescue nil
    client.close
  end

  def client_establish!
    client.establish
    self.clientEstablish = true
  end

  private def reject_establish!
    return if clientEstablish

    client.reject_establish!
  end

  def reject_establish
    reject_establish! rescue nil

    all_close
  end
end
