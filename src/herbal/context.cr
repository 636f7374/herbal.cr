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

    remote.try { |_remote| self.remote = _remote }
    remote.try &.read_timeout = timeout.read
    remote.try &.write_timeout = timeout.write

    remote
  end

  def all_close
    client.close rescue nil
    remote.close rescue nil
  end

  def heartbeat_proc : Proc(Nil)?
    is_client_herbal = client.try &.is_a? Herbal::Socket
    is_remote_herbal = remote.try &.is_a? Herbal::Socket || remote.try &.is_a? Herbal::Client

    if is_client_herbal || is_remote_herbal
      ->do
        _client = client

        if _client.is_a? Herbal::Socket
          client_wrapped = _client.wrapped
          client_wrapped.ping if client_wrapped.is_a? Herbal::Plugin::WebSocket::Stream
        end

        _remote = remote

        if _remote.is_a?(Herbal::Socket) || _remote.is_a?(Herbal::Client)
          remote_wrapped = _remote.wrapped
          remote_wrapped.ping if remote_wrapped.is_a? Herbal::Plugin::WebSocket::Stream
        end

        nil
      end
    end
  end

  def transport(reliable : Transport::Reliable)
    _transport = Transport.new client, remote, heartbeat: heartbeat_proc
    _transport.reliable = reliable
    _transport.perform

    waiting_transport _transport
  end

  private def waiting_transport(transport : Transport)
    keep_alive_proc = ->do
      client_wrapped = client.wrapped
      return false unless client_wrapped.is_a? Herbal::Plugin::WebSocket::Stream
      return false unless need_disconnect_peer = client_wrapped.need_disconnect_peer?

      case client_wrapped.keep_alive?
      when true
        transport.cleanup_side Transport::Side::Remote, free_tls: true

        client.active = false
        client_wrapped.need_disconnect_peer = nil

        return true
      when false
        transport.cleanup_all

        client.active = false
        client_wrapped.need_disconnect_peer = nil

        return true
      end
    end

    loop do
      break if keep_alive_proc.call

      if transport.reliable_status.call
        transport.cleanup_all
        client.active = false

        break
      end

      next sleep 0.25_f32
    end
  end

  def perform(reliable : Transport::Reliable = Transport::Reliable::Half)
    begin
      connect_remote!
    rescue ex
      return all_close
    end

    transport reliable
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
