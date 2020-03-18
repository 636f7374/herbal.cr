module Tomato
  class Context
    getter client : Socket
    getter dnsResolver : Durian::Resolver
    property timeout : TimeOut
    property clientEstablish : Bool
    property server : IO

    def initialize(@client : Socket, @dnsResolver : Durian::Resolver, @timeout : TimeOut = TimeOut.new)
      @clientEstablish = false
      @server = Tomato.empty_io
    end

    def server=(value : IO)
      @server = value
    end

    def server
      @server
    end

    private def upstream_finished=(value : Bool)
      @upstreamFinished = value
    end

    private def upstream_finished?
      @upstreamFinished
    end

    private def downstream_finished=(value : Bool)
      @downstreamFinished = value
    end

    private def downstream_finished?
      @downstreamFinished
    end

    private def all_closed=(value : Bool)
      @allClosed = value
    end

    private def all_closed?
      @allClosed
    end

    def stats
      Stats.from_socket client
    end

    def connect_server!
      return unless server.is_a? IO::Memory if server
      raise UnknownFlag.new unless command = client.command
      raise UnEstablish.new unless clientEstablish
      raise UnknownFlag.new unless remote_address = client.remote_address

      host = remote_address.host
      port = remote_address.port

      case command
      when .tcp_connection?
        remote = Durian::TCPSocket.connect host, port, dnsResolver, timeout.connect
      when .tcp_binding?
        remote = Durian::TCPSocket.connect host, port, dnsResolver, timeout.connect
        remote.reuse_address = true
        remote.reuse_port = true
        remote.bind remote.local_address
        remote.listen
      when .associate_udp?
        remote = Durian::Resolver.get_udp_socket! host, port, dnsResolver
      end

      self.server = remote if remote
      remote.try &.read_timeout = timeout.read
      remote.try &.write_timeout = timeout.write

      remote
    end

    def all_close
      client.close rescue nil
      server.close rescue nil
    end

    def transport
      all_transport client, server
    end

    def all_transport(client, server : IO)
      spawn do
        IO.copy client, server rescue nil
        self.upstream_finished = true
      end

      spawn do
        IO.copy server, client rescue nil
        self.downstream_finished = true
      end

      spawn do
        loop do
          break Fiber.yield if all_closed?

          if upstream_finished? || downstream_finished?
            all_close

            break self.all_closed = true
          end

          Fiber.yield
        end
      end
    end

    def perform
      begin
        connect_server!
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
end
