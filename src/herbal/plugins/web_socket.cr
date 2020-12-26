module Herbal::Plugin
  module WebSocket
    class Stream < IO
      alias Opcode = HTTP::WebSocket::Protocol::Opcode
      alias Protocol = HTTP::WebSocket::Protocol

      enum EnhancedPing : UInt8
        KeepAlive = 0_u8
      end

      enum EnhancedPong : UInt8
        Confirmed = 0_u8
        Refused   = 1_u8
      end

      property wrapped : Protocol
      property windowRemaining : Int32
      property option : Herbal::Option?
      getter buffer : IO::Memory
      getter mutex : Mutex

      def initialize(@wrapped : Protocol, @windowRemaining : Int32 = 0_i32, @option : Herbal::Option? = nil)
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

      def keep_alive=(value : Bool?)
        @keepAlive = value
      end

      def keep_alive?
        @keepAlive
      end

      def need_disconnect_peer=(value : Bool?)
        @needDisconnectPeer = value
      end

      def need_disconnect_peer?
        @needDisconnectPeer
      end

      private def update_buffer
        receive_buffer = uninitialized UInt8[4096_i32]

        loop do
          receive = wrapped.receive receive_buffer.to_slice

          case receive.opcode
          when .binary?
            self.windowRemaining = receive.size

            buffer.rewind
            buffer.clear

            buffer.write receive_buffer.to_slice[0_i32, receive.size]

            break buffer.rewind
          when .ping?
            slice = receive_buffer.to_slice[0_i32, receive.size]

            next unless 1_i32 == slice.size
            enhanced_ping = EnhancedPing.from_value slice.first rescue nil

            case enhanced_ping
            when EnhancedPing::KeepAlive
              @mutex.synchronize do
                allow_keep_alive = option.try &.allowKeepAlive

                if allow_keep_alive
                  wrapped.pong Bytes[EnhancedPong::Confirmed.to_i]

                  self.keep_alive = true
                  self.need_disconnect_peer = true
                else
                  wrapped.pong Bytes[EnhancedPong::Refused.to_i]

                  self.keep_alive = false
                  self.need_disconnect_peer = true
                end
              end

              raise Exception.new "NoticedKeepAlive"
            else
              @mutex.synchronize { wrapped.pong }
            end
          end
        end
      end

      def receive_pong_event! : EnhancedPong
        receive_buffer = uninitialized UInt8[4096_i32]

        loop do
          receive = wrapped.receive receive_buffer.to_slice

          case receive.opcode
          when .pong?
            slice = receive_buffer.to_slice[0_i32, receive.size]

            next unless 1_i32 == slice.size
            enhanced_pong = EnhancedPong.from_value slice.first rescue nil
            next unless enhanced_pong

            break enhanced_pong
          end
        end
      end

      def ping(event : EnhancedPing? = nil)
        message = Bytes[event.to_i] if event

        @mutex.synchronize { wrapped.ping message }
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
