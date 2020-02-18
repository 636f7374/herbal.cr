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

    def summary
      Summary.from_socket client
    end

    def connect_server!
      return unless server.is_a? IO::Memory if server

      raise UnEstablish.new unless clientEstablish
      raise UnknownFlag.new unless remote_ip_address = client.remote_ip_address
      raise UnknownFlag.new unless command = client.command

      case command
      when .tcp_connection?
        remote = TCPSocket.new remote_ip_address, timeout.connect
      when .tcp_binding?
        remote = TCPSocket.new remote_ip_address, timeout.connect

        remote.reuse_address = true
        remote.reuse_port = true
        remote.bind remote.local_address
        remote.listen
      when .associate_udp?
        remote = UDPSocket.new remote_ip_address.family
        remote.connect remote_ip_address
      end

      @server = remote if remote
      remote.try &.read_timeout = timeout.read
      remote.try &.write_timeout = timeout.write

      remote
    end

    def all_close
      client.close
      server.close
    end

    def transport
      transport client, server
    end

    def transport(client, server : IO)
      channel = Channel(Bool).new

      spawn do
        IO.copy client, server rescue nil
        channel.send true
      end

      spawn do
        IO.copy server, client rescue nil
        channel.send true
      end

      if channel.receive
        client.close rescue nil
        server.close rescue nil
      end

      channel.receive
    end

    def perform
      begin
        connect_server!
      rescue ex
        server.close
        client.close

        return
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

    def reject_establish!
      return if clientEstablish

      client.reject_establish!
      client.close
    end
  end
end
