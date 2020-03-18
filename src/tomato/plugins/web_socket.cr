module Tomato::Plugin::WebSocket
  class Window
    property all : Int32
    property remaining : Int32

    def initialize(@all : Int32 = 0_i32, @remaining : Int32 = 0_i32)
    end
  end

  class Stream < IO
    alias Opcode = HTTP::WebSocket::Protocol::Opcode
    alias Protocol = HTTP::WebSocket::Protocol

    property wrapped : Protocol
    property window : Window
    property buffer : IO::Memory

    def initialize(@wrapped : Protocol)
      @window = Window.new
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

    def all_free
      _wrapped = wrapped
      _wrapped.all_free if _wrapped.responds_to? :all_free
    end

    private def update_buffer
      receive_buffer = uninitialized UInt8[4096_i32]

      loop do
        receive = wrapped.receive receive_buffer.to_slice

        case receive.opcode
        when Opcode::TEXT, Opcode::BINARY
          window.all = receive.size
          window.remaining = receive.size

          buffer.rewind ensure buffer.clear
          buffer.write receive_buffer.to_slice[0_i32, receive.size]

          break buffer.rewind
        end
      end
    end

    private def update_window
      case {window.all, window.remaining}
      when {0_i32, window.remaining}
        update_buffer
      when {window.all, 0_i32}
        update_buffer
      end
    end

    def read(slice : Bytes) : Int32
      update_window

      length = buffer.read slice
      window.remaining -= length

      length
    end

    def write(slice : Bytes) : Nil
      wrapped.send slice
    end

    def <<(value : String)
      wrapped.send value

      self
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
