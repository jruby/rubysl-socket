class Addrinfo
  attr_reader :afamily, :pfamily, :socktype, :protocol, :unix_path

  attr_reader :canonname

  def self.getaddrinfo(nodename, service, family = nil, socktype = nil,
                       protocol = nil, flags = nil)

    raw = Socket
      .getaddrinfo(nodename, service, family, socktype, protocol, flags)

    raw.map do |pair|
      lfamily, lport, lhost, laddress, _, lsocktype, lprotocol = pair

      sockaddr = Socket.pack_sockaddr_in(lport, laddress)
      addr     = Addrinfo.new(sockaddr, lfamily, lsocktype, lprotocol)

      if flags and flags | Socket::AI_CANONNAME
        addr.instance_variable_set(:@canonname, lhost)
      end

      addr
    end
  end

  def self.ip(ip)
    sockaddr = Socket.sockaddr_in(0, ip)
    family   = RubySL::Socket.family_for_sockaddr_in(sockaddr)

    new(sockaddr, family)
  end

  def self.tcp(ip, port)
    sockaddr = Socket.sockaddr_in(port, ip)
    pfamily  = RubySL::Socket.family_for_sockaddr_in(sockaddr)

    new(sockaddr, pfamily, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)
  end

  def self.udp(ip, port)
    sockaddr = Socket.sockaddr_in(port, ip)
    pfamily  = RubySL::Socket.family_for_sockaddr_in(sockaddr)

    new(sockaddr, pfamily, Socket::SOCK_DGRAM, Socket::IPPROTO_UDP)
  end

  def self.unix(socket, socktype = nil)
    socktype ||= Socket::SOCK_STREAM

    new(Socket.pack_sockaddr_un(socket), Socket::PF_UNIX, socktype)
  end

  def initialize(sockaddr, pfamily = nil, socktype = 0, protocol = 0)
    if sockaddr.kind_of?(Array)
      @afamily    = RubySL::Socket::Helpers.address_family(sockaddr[0])
      @ip_port    = sockaddr[1]
      @ip_address = sockaddr[3]
    else
      if sockaddr.bytesize == Rubinius::FFI.config('sockaddr_un.sizeof')
        @unix_path = Socket.unpack_sockaddr_un(sockaddr)
        @afamily   = Socket::AF_UNIX
      else
        @ip_port, @ip_address = Socket.unpack_sockaddr_in(sockaddr)

        if sockaddr.bytesize == 28
          @afamily = Socket::AF_INET6
        else
          @afamily = Socket::AF_INET
        end
      end
    end

    @pfamily ||= RubySL::Socket::Helpers.protocol_family(pfamily)

    @socktype = RubySL::Socket::Helpers.socket_type(socktype || 0)
    @protocol = protocol || 0

    # Per MRI behaviour setting the protocol family should also set the address
    # family, but only if the address and protocol families are compatible.
    if @pfamily && @pfamily != 0
      if @afamily == Socket::AF_INET6 and
      @pfamily != Socket::PF_INET and
      @pfamily != Socket::PF_INET6
        raise SocketError, 'The given protocol and address families are incompatible'
      end

      @afamily = @pfamily
    end

    # When using AF_INET6 the protocol family can only be PF_INET6
    if @afamily == Socket::AF_INET6
      @pfamily = Socket::PF_INET6
    end

    # MRI only checks this if "sockaddr" is an Array.
    if sockaddr.kind_of?(Array)
      if @afamily == Socket::AF_INET6
        if Socket.sockaddr_in(0, @ip_address).bytesize != 28
          raise SocketError, "Invalid IPv6 address: #{@ip_address.inspect}"
        end
      end
    end

    # Based on MRI's (re-)implementation of getaddrinfo()
    if @afamily != Socket::AF_UNIX and
    @afamily != Socket::PF_UNSPEC and
    @afamily != Socket::PF_INET and
    @afamily != Socket::PF_INET6
      raise(
        SocketError,
        'Address family must be AF_UNIX, AF_INET, AF_INET6, PF_INET or PF_INET6'
      )
    end

    # Per MRI this validation should only happen when "sockaddr" is an Array.
    if sockaddr.is_a?(Array)
      case @socktype
      when 0, nil
        if @protocol != 0 and @protocol != nil and @protocol != Socket::IPPROTO_UDP
          raise SocketError, 'Socket protocol must be IPPROTO_UDP or left unset'
        end
      when Socket::SOCK_RAW
        # nothing to do
      when Socket::SOCK_DGRAM
        if @protocol != Socket::IPPROTO_UDP and @protocol != 0
          raise SocketError, 'Socket protocol must be IPPROTO_UDP or left unset'
        end
      when Socket::SOCK_STREAM
        if @protocol != Socket::IPPROTO_TCP and @protocol != 0
          raise SocketError, 'Socket protocol must be IPPROTO_TCP or left unset'
        end
      # Based on MRI behaviour, though MRI itself doesn't seem to explicitly
      # handle this case (possibly handled by getaddrinfo()).
      when Socket::SOCK_SEQPACKET
        if @protocol != 0
          raise SocketError, 'SOCK_SEQPACKET can not be used with an explicit protocol'
        end
      else
        raise SocketError, 'Unsupported socket type'
      end
    end
  end

  def unix?
    @afamily == Socket::AF_UNIX
  end

  def ipv4?
    @afamily == Socket::AF_INET
  end

  def ipv6?
    @afamily == Socket::AF_INET6
  end

  def ip?
    ipv4? || ipv6?
  end

  def ip_address
    unless ip?
      raise SocketError, 'An IPv4/IPv6 address is required'
    end

    @ip_address
  end

  def ip_port
    unless ip?
      raise SocketError, 'An IPv4/IPv6 address is required'
    end

    @ip_port
  end

  def to_sockaddr
    if unix?
      Socket.sockaddr_un(@unix_path)
    else
      Socket.sockaddr_in(@ip_port.to_i, @ip_address.to_s)
    end
  end
end
