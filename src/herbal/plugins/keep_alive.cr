module Herbal::Plugin::KeepAlive
  class Window
    property all : Int64
    property remaining : Int64

    def initialize(@all : Int64 = 0_i64, @remaining : Int64 = 0_i64)
    end
  end

  class Client < IO
    property wrapped : IO
    property host : String
    property method : String
    property path : String
    property window : Window

    def initialize(@wrapped : IO, @host : String)
      @method = "GET"
      @path = "/"
      @window = Window.new
    end

    def self.new(wrapped : IO, host : String, port : Int32)
      new wrapped, String.build { |io| io << host << ":" << port.to_s }
    end

    def read_timeout=(value : Int | Float | Time::Span | Nil)
      _wrapped = wrapped
      _wrapped.read_timeout = value if value if _wrapped.responds_to? :read_timeout=
    end

    def write_timeout=(value : Int | Float | Time::Span | Nil)
      _wrapped = wrapped
      _wrapped.write_timeout = value if value if _wrapped.responds_to? :write_timeout=
    end

    def read_timeout
      _wrapped = wrapped
      _wrapped.read_timeout if _wrapped.responds_to? :read_timeout
    end

    def write_timeout
      _wrapped = wrapped
      _wrapped.write_timeout if _wrapped.responds_to? :write_timeout
    end

    private def from_io
      HTTP::Client::Response.from_io wrapped, ignore_body: true
    end

    private def update_window
      finished = false

      case {window.all, window.remaining}
      when {0_i64, window.remaining}
        finished = true
      when {window.all, 0_i64}
        finished = true
      end

      return unless finished

      payload = from_io
      window.all = payload.content_length
      window.remaining = payload.content_length
    end

    def read(slice : Bytes) : Int32
      update_window

      length = (window.remaining >= slice.size) ? slice.size : window.remaining

      temporary = IO::Memory.new length
      length = IO.copy wrapped, temporary, length
      temporary.rewind

      length = temporary.read slice
      window.remaining -= length

      length
    end

    def write(slice : Bytes) : Nil
      write_payload slice
    end

    def <<(value : String)
      write_payload value

      self
    end

    def write_payload(slice : Bytes)
      write_payload String.new slice
    end

    def write_payload(value : String)
      payload = HTTP::Request.new method, path, body: value
      payload.header_keep_alive = true
      payload.header_host = host
      payload.to_io wrapped
    end

    def flush
      wrapped.flush
    end

    def close
      wrapped.close
    end

    def closed?
      wrapped.closed?
    end
  end

  class Server < IO
    property wrapped : IO
    property statusCode : Int32
    property window : Window

    def initialize(@wrapped : IO)
      @statusCode = 200_i32
      @window = Window.new
    end

    def read_timeout=(value : Int | Float | Time::Span | Nil)
      _wrapped = wrapped
      _wrapped.read_timeout = value if value if _wrapped.responds_to? :read_timeout=
    end

    def write_timeout=(value : Int | Float | Time::Span | Nil)
      _wrapped = wrapped
      _wrapped.write_timeout = value if value if _wrapped.responds_to? :write_timeout=
    end

    def read_timeout
      _wrapped = wrapped
      _wrapped.read_timeout if _wrapped.responds_to? :read_timeout
    end

    def write_timeout
      _wrapped = wrapped
      _wrapped.write_timeout if _wrapped.responds_to? :write_timeout
    end

    private def from_io
      HTTP::Request.from_io wrapped
    end

    private def update_window
      finished = false

      case {window.all, window.remaining}
      when {0_i64, window.remaining}
        finished = true
      when {window.all, 0_i64}
        finished = true
      end

      return unless finished

      payload = from_io
      raise MalformedPacket.new unless payload.is_a? HTTP::Request

      window.all = payload.content_length
      window.remaining = payload.content_length
    end

    def read(slice : Bytes) : Int32
      return 0_i32 if slice.empty?

      update_window

      length = (window.remaining >= slice.size) ? slice.size : window.remaining

      temporary = IO::Memory.new length
      length = IO.copy wrapped, temporary, length
      temporary.rewind

      length = temporary.read slice
      window.remaining -= length

      length
    end

    def write(slice : Bytes) : Nil
      write_payload slice
    end

    def <<(value : String)
      write_payload value

      self
    end

    def write_payload(slice : Bytes)
      write_payload String.new slice
    end

    def write_payload(value : String)
      payload = HTTP::Client::Response.new statusCode, body: value
      payload.header_keep_alive = true
      payload.to_io wrapped
    end

    def flush
      wrapped.flush
    end

    def close
      wrapped.close
    end

    def closed?
      wrapped.closed?
    end
  end
end
