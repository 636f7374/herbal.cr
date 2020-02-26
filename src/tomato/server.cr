module Tomato
  class Server
    getter wrapped : ::Socket::Server
    getter dnsResolver : Durian::Resolver

    def initialize(@wrapped : ::Socket::Server, @dnsResolver : Durian::Resolver)
    end

    def authentication=(value : Authentication)
      @authentication = value
    end

    def authentication
      @authentication || Authentication::NoAuthentication
    end

    def on_auth=(value : Proc(String, String?, Tomato::Verify))
      @onAuth = value
    end

    def on_auth
      @onAuth
    end

    def client_timeout=(value : TimeOut)
      @clientTimeOut = value
    end

    def client_timeout
      @clientTimeOut
    end

    def remote_timeout=(value : TimeOut)
      @remoteTimeOut = value
    end

    def remote_timeout
      @remoteTimeOut
    end

    def process!(socket : Socket, sync_resolution : Bool = false, skip_establish : Bool = false) : Socket
      # HandShake
      begin
        handshake = socket.handshake!

        raise AuthenticationFailed.new if handshake.deny?
      rescue ex
        socket.close

        raise ex
      end

      # Process
      begin
        socket.process! sync_resolution
      rescue ex
        socket.close

        raise ex
      end

      # Establish
      return socket if skip_establish

      begin
        socket.establish! sync_resolution
      rescue ex
        socket.close

        raise ex
      end

      socket
    end

    def process(socket : Socket, sync_resolution : Bool = false, skip_establish : Bool = false) : Socket?
      process! socket, sync_resolution, skip_establish rescue nil
    end

    def upgrade!(socket : Socket, sync_resolution : Bool = false, skip_establish : Bool = false) : Context
      process! socket, sync_resolution, skip_establish

      context = Context.new socket, dnsResolver
      remote_timeout.try { |_timeout| context.timeout = _timeout }
      context.clientEstablish = true unless skip_establish

      context
    end

    def upgrade(socket : Socket, sync_resolution : Bool = false, skip_establish : Bool = false) : Context?
      upgrade! socket, sync_resolution, skip_establish rescue nil
    end

    def accept? : Socket?
      return unless socket = wrapped.accept?
      _socket = Socket.new socket, dnsResolver

      # Attach
      on_auth.try { |_on_auth| _socket.on_auth = _on_auth }
      authentication.try { |_authentication| _socket.authentication = _authentication }

      # TimeOut
      client_timeout.try do |_timeout|
        _socket.read_timeout = _timeout.read
        _socket.write_timeout = _timeout.write
      end

      _socket
    end
  end
end
