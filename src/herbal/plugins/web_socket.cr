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
      property windowRemaining : Atomic(Int32)
      property option : Herbal::Option?
      getter buffer : IO::Memory
      getter ioMutex : Mutex
      getter mutex : Mutex

      def initialize(@wrapped : Protocol, @windowRemaining : Atomic(Int32) = Atomic(Int32).new(0_i32), @option : Herbal::Option? = nil)
        @buffer = IO::Memory.new
        @ioMutex = Mutex.new :unchecked
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
        @mutex.synchronize { @keepAlive = value }
      end

      def keep_alive?
        @mutex.synchronize { @keepAlive }
      end

      def need_disconnect_peer=(value : Bool?)
        @mutex.synchronize { @needDisconnectPeer = value }
      end

      def need_disconnect_peer?
        @mutex.synchronize { @needDisconnectPeer }
      end

      private def update_buffer
        receive_buffer = uninitialized UInt8[4096_i32]

        loop do
          receive = wrapped.receive receive_buffer.to_slice

          case receive.opcode
          when .binary?
            self.windowRemaining.set receive.size

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
              allow_keep_alive = option.try &.allowKeepAlive

              if allow_keep_alive
                pong EnhancedPong::Confirmed

                self.keep_alive = true
                self.need_disconnect_peer = true
              else
                pong EnhancedPong::Refused

                self.keep_alive = false
                self.need_disconnect_peer = true
              end

              raise Exception.new "NoticedKeepAlive"
            else
              pong nil
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

      def pong(event : EnhancedPong? = nil)
        message = Bytes[event.to_i] if event

        @ioMutex.synchronize { wrapped.pong message }
      end

      def ping(event : EnhancedPing? = nil)
        message = Bytes[event.to_i] if event

        @ioMutex.synchronize { wrapped.ping message }
      end

      def read(slice : Bytes) : Int32
        return 0_i32 if slice.empty?
        update_buffer if windowRemaining.get.zero?

        length = buffer.read slice
        self.windowRemaining.add -length

        length
      end

      def write(slice : Bytes) : Nil
        @ioMutex.synchronize { wrapped.send slice }
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
