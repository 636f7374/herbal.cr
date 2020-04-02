module Tomato
  class Context
    getter client : Socket
    getter dnsResolver : Durian::Resolver
    property timeout : TimeOut
    property clientEstablish : Bool
    property remote : IO

    def initialize(@client : Socket, @dnsResolver : Durian::Resolver, @timeout : TimeOut = TimeOut.new)
      @clientEstablish = false
      @remote = Tomato.empty_io
    end

    def remote=(value : IO)
      @remote = value
    end

    def remote
      @remote
    end

    private def uploaded_size=(value : UInt64)
      @uploadedSize = value
    end

    private def uploaded_size
      @uploadedSize
    end

    private def received_size=(value : UInt64)
      @receivedSize = value
    end

    private def received_size
      @receivedSize
    end

    def stats
      Stats.from_socket client
    end

    def connect_remote!
      return unless remote.is_a? IO::Memory if remote
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
      all_transport client, remote
    end

    def all_transport(client, remote : IO)
      spawn do
        exception = nil
        count = 0_u64

        loop do
          size = begin
            IO.copy client, remote, true
          rescue ex : IO::CopyException
            exception = ex.cause
            ex.count
          rescue
            nil
          end

          size.try { |_size| count += _size }

          if exception && count.try &.zero?
            break unless exception.is_a? IO::Timeout
            next unless received_size
          end

          break
        end

        self.uploaded_size = count || 0_u64
      end

      spawn do
        exception = nil
        count = 0_u64

        loop do
          size = begin
            IO.copy remote, client, true
          rescue ex : IO::CopyException
            exception = ex.cause
            ex.count
          rescue
            nil
          end

          size.try { |_size| count += _size }

          if exception && count.try &.zero?
            break unless exception.is_a? IO::Timeout
            next unless uploaded_size
          end

          break
        end

        self.received_size = count || 0_u64
      end

      spawn do
        loop do
          if uploaded_size && received_size
            client.close rescue nil
            break remote.close rescue nil
          end

          sleep 1_i32.seconds
        end
      end
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
end
