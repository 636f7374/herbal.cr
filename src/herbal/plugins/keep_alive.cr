module Herbal::Plugin
  module KeepAlive
    class Client < IO
      property wrapped : IO
      property host : String
      property windowRemaining : Atomic(Int64)
      property method : String
      property path : String

      def initialize(@wrapped : IO, @host : String, @windowRemaining : Atomic(Int64) = Atomic(Int64).new 0_i64)
        @method = "GET"
        @path = "/"
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
        _end = false
        _end = true if windowRemaining.get.zero?
        return unless _end

        payload = from_io
        self.windowRemaining.set payload.content_length
      end

      def read(slice : Bytes) : Int32
        return 0_i32 if slice.empty?

        update_window
        length = (self.windowRemaining.get >= slice.size) ? slice.size : self.windowRemaining.get

        temporary = IO::Memory.new length
        length = IO.copy wrapped, temporary, length
        temporary.rewind

        length = temporary.read slice
        self.windowRemaining.add -length.to_i64

        length
      end

      def write(slice : Bytes) : Nil
        write_payload slice
      end

      def write_payload(slice : Bytes) : Int64
        write_payload String.new slice
      end

      def write_payload(value : String) : Int64
        payload = HTTP::Request.new method, path, body: value

        payload.header_keep_alive = true
        payload.header_host = host
        payload.to_io wrapped

        value.size.to_i64
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
      property windowRemaining : Atomic(Int64)
      property statusCode : Int32

      def initialize(@wrapped : IO, @windowRemaining : Atomic(Int64) = Atomic(Int64).new 0_i64)
        @statusCode = 200_i32
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
        _end = false
        _end = true if windowRemaining.get.zero?
        return unless _end

        payload = from_io
        raise MalformedPacket.new unless payload.is_a? HTTP::Request

        self.windowRemaining.set payload.content_length
      end

      def read(slice : Bytes) : Int32
        return 0_i32 if slice.empty?

        update_window
        length = (self.windowRemaining.get >= slice.size) ? slice.size : self.windowRemaining.get

        temporary = IO::Memory.new length
        length = IO.copy wrapped, temporary, length
        temporary.rewind

        length = temporary.read slice
        self.windowRemaining.add -length.to_i64

        length
      end

      def write(slice : Bytes) : Nil
        write_payload slice
      end

      def write_payload(slice : Bytes) : Int64
        write_payload String.new slice
      end

      def write_payload(value : String) : Int64
        payload = HTTP::Client::Response.new statusCode, body: value

        payload.header_keep_alive = true
        payload.to_io wrapped

        value.size.to_i64
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
end
