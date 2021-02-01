class Herbal::Server
  getter wrapped : ::Socket::Server
  getter dnsResolver : Durian::Resolver
  getter option : Herbal::Option?

  def initialize(@wrapped : ::Socket::Server, @dnsResolver : Durian::Resolver, @option : Herbal::Option? = nil)
  end

  def self.new(host : String, port : Int32, dns_resolver : Durian::Resolver, option : Herbal::Option? = nil)
    tcp_server = TCPServer.new host, port
    new wrapped: tcp_server, dnsResolver: dns_resolver, option: option
  end

  def authentication=(value : Authentication)
    @authentication = value
  end

  def authentication
    @authentication || Authentication::NoAuthentication
  end

  def on_auth=(value : Proc(String, String?, Herbal::Verify))
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
    # Set socket activity status to true, Set keep alive to nil
    # ** Necessary to achieve similar HTTP/1.1 pipeline feature

    socket.active = true
    socket.reset_keep_alive

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
      raise BadDestinationAddress.new if socket.bad_destination_address?
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
    context.sourceEstablish = true unless skip_establish

    remote_timeout.try { |_timeout| context.timeout = _timeout }

    context
  end

  def upgrade(socket : Socket, sync_resolution : Bool = false, skip_establish : Bool = false) : Context?
    upgrade! socket, sync_resolution, skip_establish rescue nil
  end

  def accept? : Socket?
    return unless socket = wrapped.accept?
    _socket = Socket.new socket, dnsResolver, option

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
