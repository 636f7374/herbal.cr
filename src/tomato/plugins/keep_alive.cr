module Tomato::Plugin::KeepAlive
  class Progress
    property contentLength : Int64
    property remaining : Int64

    def initialize(@contentLength : Int64 = 0_i64, @remaining : Int64 = 0_i64)
    end
  end

  class Client < IO
    property wrapped : IO
    property host : String
    property method : String
    property path : String
    property progress : Progress
    property buffer : IO::Memory

    def initialize(@wrapped : IO, @host : String)
      @method = "GET"
      @path = "/"
      @progress = Progress.new
      @buffer = IO::Memory.new
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

    def buffer_close
      buffer.close
    end

    private def from_io
      HTTP::Client::Response.from_io wrapped, ignore_body: true
    end

    private def update_progress
      finished = false

      case {progress.contentLength, progress.remaining}
      when {0_i64, progress.remaining}
        finished = true
      when {progress.contentLength, 0_i64}
        finished = true
      end

      return unless finished

      payload = from_io
      progress.contentLength = payload.content_length
      progress.remaining = payload.content_length
    end

    def read(slice : Bytes) : Int32
      update_progress

      length = (progress.remaining >= slice.size) ? slice.size : progress.remaining

      temporary = IO::Memory.new length
      length = IO.copy wrapped, temporary, length
      temporary.rewind

      length = temporary.read slice
      progress.remaining -= length

      length
    end

    def write(slice : Bytes) : Nil
      return write_payload slice if buffer.closed?

      buffer.write slice
    end

    def <<(value : String)
      buffer << value

      self
    end

    def write_payload(slice : Bytes)
      payload = HTTP::Request.new method, path, body: slice
      payload.keep_alive = true
      payload.header_host = host
      payload.to_io wrapped
    end

    def flush
      return wrapped.flush if buffer.closed?

      write_payload buffer.to_slice
      buffer.rewind ensure buffer.clear
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
    property progress : Progress
    property buffer : IO::Memory

    def initialize(@wrapped : IO)
      @statusCode = 200_i32
      @progress = Progress.new
      @buffer = IO::Memory.new
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

    def buffer_close
      buffer.close
    end

    private def from_io
      HTTP::Request.from_io wrapped
    end

    private def update_progress
      finished = false

      case {progress.contentLength, progress.remaining}
      when {0_i64, progress.remaining}
        finished = true
      when {progress.contentLength, 0_i64}
        finished = true
      end

      return unless finished

      payload = from_io
      raise MalformedPacket.new unless payload.is_a? HTTP::Request

      progress.contentLength = payload.content_length
      progress.remaining = payload.content_length
    end

    def read(slice : Bytes) : Int32
      update_progress

      length = (progress.remaining >= slice.size) ? slice.size : progress.remaining

      temporary = IO::Memory.new length
      length = IO.copy wrapped, temporary, length
      temporary.rewind

      length = temporary.read slice
      progress.remaining -= length

      length
    end

    def write(slice : Bytes) : Nil
      return write_payload slice if buffer.closed?

      buffer.write slice
    end

    def <<(value : String)
      buffer << value

      self
    end

    def write_payload(slice : Bytes)
      payload = HTTP::Client::Response.new statusCode, body: String.new slice
      payload.keep_alive = true
      payload.to_io wrapped
    end

    def flush
      return wrapped.flush if buffer.closed?

      write_payload buffer.to_slice
      buffer.rewind ensure buffer.clear
    end

    def close
      wrapped.close
    end

    def closed?
      wrapped.closed?
    end
  end
end
