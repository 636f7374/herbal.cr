module Tomato::Plugin::WebSocket
  class Progress
    property payloadLength : Int32
    property remaining : Int32

    def initialize(@payloadLength : Int32 = 0_i32, @remaining : Int32 = 0_i32)
    end
  end

  class Stream < IO
    alias Opcode = HTTP::WebSocket::Protocol::Opcode
    alias Protocol = HTTP::WebSocket::Protocol

    property wrapped : Protocol
    property progress : Progress
    property buffer : IO::Memory

    def initialize(@wrapped : Protocol)
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
          progress.payloadLength = receive.size
          progress.remaining = receive.size

          buffer.rewind ensure buffer.clear
          buffer.write receive_buffer.to_slice[0_i32, receive.size]

          break buffer.rewind
        end
      end
    end

    private def update_progress
      case {progress.payloadLength, progress.remaining}
      when {0_i32, progress.remaining}
        update_buffer
      when {progress.payloadLength, 0_i32}
        update_buffer
      end
    end

    def read(slice : Bytes) : Int32
      update_progress

      length = buffer.read slice
      progress.remaining -= length

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
