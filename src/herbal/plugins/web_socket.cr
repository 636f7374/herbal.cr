module Herbal::Plugin
  module WebSocket
    class Stream < IO
      alias Opcode = HTTP::WebSocket::Protocol::Opcode
      alias Protocol = HTTP::WebSocket::Protocol

      property wrapped : Protocol
      property windowRemaining : Int32
      property buffer : IO::Memory
      getter mutex : Mutex

      def initialize(@wrapped : Protocol, @windowRemaining : Int32 = 0_i32)
        @buffer = IO::Memory.new
        @mutex = Mutex.new :unchecked
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

      private def update_buffer
        receive_buffer = uninitialized UInt8[4096_i32]

        loop do
          receive = wrapped.receive receive_buffer.to_slice

          case receive.opcode
          when .binary?
            self.windowRemaining = receive.size

            buffer.rewind ensure buffer.clear
            buffer.write receive_buffer.to_slice[0_i32, receive.size]

            break buffer.rewind
          when .ping?
            @mutex.synchronize { wrapped.pong }
          end
        end
      end

      def ping
        @mutex.synchronize { wrapped.ping }
      end

      def read(slice : Bytes) : Int32
        return 0_i32 if slice.empty?
        update_buffer if windowRemaining.zero?

        length = buffer.read slice
        self.windowRemaining -= length

        length
      end

      def write(slice : Bytes) : Nil
        @mutex.synchronize { wrapped.send slice }
      end

      def flush
        wrapped.flush
      end

      def close
        wrapped.io_close
      end

      def closed?
        wrapped.closed?
      end
    end
  end
end
