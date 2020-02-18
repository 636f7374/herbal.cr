module Tomato
  class Server
    getter wrapped : TCPServer | UNIXServer
    getter dnsResolver : Durian::Resolver

    def initialize(@wrapped : TCPServer | UNIXServer, @dnsResolver : Durian::Resolver)
    end

    def authentication=(value : Authentication)
      @authentication = value
    end

    def authentication
      @authentication || Authentication::NoAuthentication
    end

    def simple_auth=(value : Proc(String, String?, Tomato::Verify))
      @simpleAuth = value
    end

    def simple_auth
      @simpleAuth
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

    def process!(socket : Socket, without_establish : Bool = false) : Socket
      # HandShake
      if socket.handshake.deny?
        socket.close

        raise AuthenticationFailed.new
      end

      # Process
      begin
        socket.process
      rescue ex
        socket.close

        raise ex
      end

      # Establish
      return socket if without_establish

      begin
        socket.establish
      rescue ex
        socket.close

        raise ex
      end

      socket
    end

    def process(socket : Socket, without_establish : Bool = false) : Socket?
      process! socket, without_establish rescue nil
    end

    def upgrade!(socket : Socket, without_establish : Bool = false) : Context
      process! socket, without_establish

      context = Context.new socket, dnsResolver
      remote_timeout.try { |_timeout| context.timeout = _timeout }
      context.clientEstablish = true unless without_establish

      context
    end

    def upgrade(socket : Socket, without_establish : Bool = false) : Context?
      upgrade! socket, without_establish rescue nil
    end

    def accept? : Socket?
      return unless socket = wrapped.accept?
      _socket = Socket.new socket, dnsResolver

      # Attach
      simple_auth.try { |_simple_auth| _socket.simple_auth = _simple_auth }
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
