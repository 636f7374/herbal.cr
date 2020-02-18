struct Tomato::Summary
  def initialize
  end

  def version=(value : Version?)
    @version = value
  end

  def authentication_methods=(value : Array(Authentication)?)
    @authenticationMethods = value
  end

  def command=(value : Command?)
    @command = value
  end

  def address_type=(value : Address?)
    @addressType = value
  end

  def remote_ip_address=(value : ::Socket::IPAddress?)
    @remoteIpAddress = value
  end

  def remote_address=(value : RemoteAddress?)
    @remoteAddress = value
  end

  def self.from_socket(socket : Socket)
    summary = new

    summary.version = socket.version
    summary.authentication_methods = socket.authentication_methods
    summary.command = socket.command
    summary.address_type = socket.address_type
    summary.remote_ip_address = socket.remote_ip_address
    summary.remote_address = socket.remote_address

    summary
  end
end