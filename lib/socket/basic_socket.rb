class BasicSocket < IO
  class << self
    def from_descriptor(fixnum)
      sock = allocate()
      sock.from_descriptor(fixnum)
      return sock
    end

    alias :for_fd :from_descriptor
  end

  def self.do_not_reverse_lookup=(setting)
    @no_reverse_lookup = setting
  end

  def self.do_not_reverse_lookup
    @no_reverse_lookup = true unless defined?(@no_reverse_lookup)
    @no_reverse_lookup
  end

  def from_descriptor(fixnum)
    IO.setup(self, fixnum, nil, true)

    self
  end

  def do_not_reverse_lookup=(setting)
    @no_reverse_lookup = setting
  end

  def do_not_reverse_lookup
    @no_reverse_lookup
  end

  def getsockopt(level, optname)
    level   = RubySL::Socket::SocketOptions.socket_level(level)
    optname = RubySL::Socket::SocketOptions.socket_option(level, optname)

    data     = RubySL::Socket::Foreign.getsockopt(descriptor, level, optname)
    sockaddr = RubySL::Socket::Foreign.getsockname(descriptor)

    family, _ = RubySL::Socket::Foreign.getnameinfo(
      sockaddr,
      Socket::Constants::NI_NUMERICHOST | Socket::Constants::NI_NUMERICSERV
    )

    Socket::Option.new(family, level, optname, data)
  end

  def setsockopt(level_or_option, optname=nil, optval=nil)
    level = nil

    case level_or_option
    when Socket::Option
      if !optname.nil?
        raise ArgumentError, "given 2, expected 3"
      end
      level = level_or_option.level
      optname = level_or_option.optname
      optval = level_or_option.data
    else
      if level_or_option.nil? or optname.nil?
        nb_arg = 3 - [level_or_option, optname, optval].count(nil)
        raise ArgumentError, "given #{nb_arg}, expected 3"
      end
      level = level_or_option
    end

    optval = 1 if optval == true
    optval = 0 if optval == false

    error = 0

    sockname = RubySL::Socket::Foreign.getsockname descriptor
    family = RubySL::Socket::Foreign.getnameinfo(sockname).first

    level = RubySL::Socket::SocketOptions.socket_level(level, family)
    optname = RubySL::Socket::SocketOptions.socket_option(level, optname)

    case optval
    when Fixnum then
      Rubinius::FFI::MemoryPointer.new :socklen_t do |val|
        val.write_int optval
        error = RubySL::Socket::Foreign.setsockopt(descriptor, level,
                                           optname, val,
                                           val.total)
      end
    when String then
      Rubinius::FFI::MemoryPointer.new optval.bytesize do |val|
        val.write_string optval, optval.bytesize
        error = RubySL::Socket::Foreign.setsockopt(descriptor, level,
                                           optname, val,
                                           optval.size)
      end
    else
      raise TypeError, "socket option should be a String, a Fixnum, true, or false"
    end

    Errno.handle "Unable to set socket option" unless error == 0

    return 0
  end

  def getsockname
    RubySL::Socket::Foreign.getsockname(descriptor)
  end

  def getpeername
    RubySL::Socket::Foreign.getpeername(descriptor)
  end

  def send(message, flags, to = nil)
    connect to if to

    bytes = message.bytesize
    bytes_sent = 0

    Rubinius::FFI::MemoryPointer.new :char, bytes + 1 do |buffer|
      buffer.write_string message, bytes
      bytes_sent = RubySL::Socket::Foreign.send(descriptor, buffer, bytes, flags)
      Errno.handle 'send(2)' if bytes_sent < 0
    end

    bytes_sent
  end

  def recv(bytes_to_read, flags = 0)
    return socket_recv(bytes_to_read, flags, 0)
  end

  # TODO: use scm_rights
  # TODO: ancillary data support
  def recvmsg(max_msg_len = nil, flags = 0, max_ctl_len = nil, scm_rights: false)
    socket_type = getsockopt(:SOCKET, :TYPE).int

    if socket_type == Socket::SOCK_STREAM
      grow_msg = false
      grow_ctl = false
    else
      grow_msg = max_msg_len.nil?
      grow_ctl = max_ctl_len.nil?
    end

    if grow_msg or grow_ctl
      flags |= Socket::MSG_PEEK
    end

    msg_len = max_msg_len || 4096
    ctl_len = max_ctl_len || 4096

    loop do
      msg_buffer = RubySL::Socket::Foreign.char_pointer(msg_len)
      ctl_buffer = RubySL::Socket::Foreign.char_pointer(ctl_len)

      address = RubySL::Socket::Foreign::Sockaddr_In.new
      io_vec  = RubySL::Socket::Foreign::Iovec.with_buffer(msg_buffer)

      header = RubySL::Socket::Foreign::Msghdr
        .with_buffers(ctl_buffer, address, io_vec)

      begin
        need_more = false

        retval = RubySL::Socket::Foreign
          .recvmsg(descriptor, header.pointer, flags)

        if grow_msg and header.message_truncated?
          need_more = true
          msg_len *= 2
        end

        if grow_ctl and header.control_truncated?
          need_more = true
          ctl_len *= 2
        end

        next if need_more

        msg = msg_buffer.read_string

        if address.null?
          addr = nil
        else
          addr = Addrinfo.new(address.to_s, nil, socket_type)
        end

        rflags = header.flags

        controls = nil

        return msg, addr, rflags, controls
      ensure
        msg_buffer.free
        ctl_buffer.free
        address.free
        io_vec.free
        header.free
      end
    end

    nil
  end

  def close_read
    ensure_open

    # If we were only in readonly mode, close it all together
    if @mode & ACCMODE == RDONLY
      return close
    end

    # MRI doesn't check if shutdown worked, so we don't.
    RubySL::Socket::Foreign.shutdown @descriptor, 0

    @mode = WRONLY

    nil
  end

  def close_write
    ensure_open

    # If we were only in writeonly mode, close it all together
    if @mode & ACCMODE == WRONLY
      return close
    end

    RubySL::Socket::Foreign.shutdown @descriptor, 1

    # Mark it as read only
    @mode = RDONLY

    nil
  end

  def recv_nonblock(bytes_to_read, flags = 0)
    fcntl Fcntl::F_SETFL, Fcntl::O_NONBLOCK
    socket_recv bytes_to_read, flags, 0
  rescue Errno::EWOULDBLOCK
    raise Errno::EAGAIN
  end

  def shutdown(how = 2)
    err = RubySL::Socket::Foreign.shutdown @descriptor, how
    Errno.handle "shutdown" unless err == 0
  end

  # MRI defines this method in BasicSocket and stuffs all logic in it. Since
  # inheriting classes behave differently we overwrite this method in said
  # classes. The method here exists so that code such as the following still
  # works: BasicSocket.method_defined?(:local_address).
  def local_address
    raise NotImplementedError,
      'This method must be implemented by classes inheriting from BasicSocket'
  end

  def remote_address
    raise NotImplementedError,
      'This method must be implemented by classes inheriting from BasicSocket'
  end

  def getpeereid
    RubySL::Socket::Foreign.getpeereid(descriptor)
  end
end
