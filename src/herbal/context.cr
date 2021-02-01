class Herbal::Context
  getter source : Socket
  getter dnsResolver : Durian::Resolver
  property timeout : TimeOut
  property sourceEstablish : Bool
  property destination : IO

  def initialize(@source : Socket, @dnsResolver : Durian::Resolver, @timeout : TimeOut = TimeOut.new)
    @sourceEstablish = false
    @destination = Herbal.empty_io
  end

  def destination=(value : IO)
    @destination = value
  end

  def destination
    @destination
  end

  def stats
    Stats.from_socket source
  end

  def connect_destination!
    return unless destination.is_a? IO::Memory if destination

    raise UnknownFlag.new unless command = source.command
    raise UnEstablish.new unless sourceEstablish
    raise UnknownFlag.new unless destination_address = source.destination_address

    host = destination_address.host
    port = destination_address.port

    case command
    when .tcp_connection?
      destination = Durian::TCPSocket.connect host, port, dnsResolver, timeout.connect
    when .tcp_binding?
      destination = Durian::TCPSocket.connect host, port, dnsResolver, timeout.connect
      destination.reuse_address = true
      destination.reuse_port = true
      destination.bind destination.local_address
    when .associate_udp?
      destination = Durian::Resolver.get_udp_socket! host, port, dnsResolver
    end

    destination.try { |_destination| self.destination = _destination }
    destination.try &.read_timeout = timeout.read
    destination.try &.write_timeout = timeout.write

    destination
  end

  def all_close
    source.close rescue nil
    destination.close rescue nil
  end

  def heartbeat_proc : Proc(Nil)?
    is_source_herbal = source.try &.is_a? Herbal::Socket
    is_destination_herbal = destination.try &.is_a? Herbal::Socket || destination.try &.is_a? Herbal::Client

    if is_source_herbal || is_destination_herbal
      ->do
        _source = source

        if _source.is_a? Herbal::Socket
          source_wrapped = _source.wrapped
          source_wrapped.ping if source_wrapped.is_a? Herbal::Plugin::WebSocket::Stream
        end

        _destination = destination

        if _destination.is_a?(Herbal::Socket) || _destination.is_a?(Herbal::Client)
          destination_wrapped = _destination.wrapped
          destination_wrapped.ping if destination_wrapped.is_a? Herbal::Plugin::WebSocket::Stream
        end

        nil
      end
    end
  end

  def transport(reliable : Transport::Reliable)
    _transport = Transport.new source, destination, heartbeat: heartbeat_proc
    _transport.reliable = reliable
    _transport.perform

    waiting_transport _transport
  end

  private def waiting_transport(transport : Transport)
    keep_alive_proc = ->do
      source_wrapped = source.wrapped
      return false unless source_wrapped.is_a? Herbal::Plugin::WebSocket::Stream
      return false unless need_disconnect_peer = source_wrapped.need_disconnect_peer?

      case source_wrapped.keep_alive?
      when true
        transport.cleanup_side Transport::Side::Destination, free_tls: true

        source.active = false
        source_wrapped.need_disconnect_peer = nil

        return true
      when false
        transport.cleanup_all

        source.active = false
        source_wrapped.need_disconnect_peer = nil

        return true
      end
    end

    loop do
      break if keep_alive_proc.call

      if transport.reliable_status.call
        transport.cleanup_all
        source.active = false

        break
      end

      next sleep 0.25_f32
    end
  end

  def perform(reliable : Transport::Reliable = Transport::Reliable::Half)
    begin
      connect_destination!
    rescue ex
      return all_close
    end

    transport reliable
  end

  def source_establish
    source_establish rescue nil
  end

  def reject_establish
    reject_establish rescue nil
    source.close
  end

  def source_establish!
    source.establish
    self.sourceEstablish = true
  end

  private def reject_establish!
    return if sourceEstablish

    source.reject_establish!
  end

  def reject_establish
    reject_establish! rescue nil

    all_close
  end
end
