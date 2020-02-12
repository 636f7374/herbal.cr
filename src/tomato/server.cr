module Tomato
  class Server
    property wrapped : TCPServer | UNIXServer

    def initialize(@wrapped : TCPServer | UNIXServer)
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

    def dns_resolver=(value : Durian::Resolver)
      @dnsResolver = value
    end

    def dns_resolver
      @dnsResolver
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

    def process!(socket : Socket, without_establish : Bool = false) : Context
      # Attach
      simple_auth.try { |_simple_auth| socket.simple_auth = _simple_auth }
      authentication.try { |_authentication| socket.authentication = _authentication }
      dns_resolver.try { |_resolver| socket.dns_resolver = _resolver }

      # TimeOut
      client_timeout.try do |_timeout|
        socket.read_timeout = _timeout.read
        socket.write_timeout = _timeout.write
      end

      # Context
      context = Context.new socket
      dns_resolver.try { |_resolver| context.dns_resolver = _resolver }
      remote_timeout.try { |_timeout| context.timeout = _timeout }

      # HandShake
      if socket.handshake.deny?
        socket.close

        raise AuthenticationFailed.new
      end

      socket.process

      # Establish
      return context if without_establish
      socket.establish

      context.clientEstablish = true
      context
    end

    def process(socket : Socket, without_establish : Bool = false) : Context?
      begin
        process! socket, without_establish
      rescue ex
        socket.close

        return
      end
    end

    def accept? : Socket?
      return unless socket = wrapped.accept?

      Socket.new socket
    end
  end
end
