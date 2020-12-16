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

  def heartbeat_proc : Proc(Nil)?
    return unless client_wrapped = client.wrapped
    return unless client_wrapped.is_a? Plugin::WebSocket::Stream

    ->do
      return unless client_wrapped = client.wrapped
      client_wrapped.ping if client_wrapped.is_a? Plugin::WebSocket::Stream
    end
  end

  def transport(side : Transport::Side = Transport::Side::Server)
    _transport = Transport.new client, remote, heartbeat: heartbeat_proc
    _transport.perform
    _transport.side = Transport::Side::Server

    loop do
      status = ->do
        case _transport.side
        when Transport::Side::Client
          _transport.uploaded_size || _transport.received_size
        else
          _transport.uploaded_size && _transport.received_size
        end
      end

      return _transport.cleanup if status.call

      next sleep 0.05_f32
    end
  end

  def perform(side : Transport::Side = Transport::Side::Server)
    begin
      connect_remote!
    rescue ex
      return all_close
    end

    transport side
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
