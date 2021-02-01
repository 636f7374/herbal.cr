struct Herbal::Stats
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

  def destination_ip_address=(value : ::Socket::IPAddress?)
    @destinationIpAddress = value
  end

  def destination_address=(value : DestinationAddress?)
    @destinationAddress = value
  end

  def self.from_socket(socket : Socket)
    stats = new

    stats.version = socket.version
    stats.authentication_methods = socket.authentication_methods
    stats.command = socket.command
    stats.address_type = socket.address_type
    stats.destination_ip_address = socket.destination_ip_address
    stats.destination_address = socket.destination_address

    stats
  end
end
