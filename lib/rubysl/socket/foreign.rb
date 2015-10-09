module RubySL
  module Socket
    module Foreign
      extend Rubinius::FFI::Library

      class Addrinfo < Rubinius::FFI::Struct
        config("rbx.platform.addrinfo", :ai_flags, :ai_family, :ai_socktype,
               :ai_protocol, :ai_addrlen, :ai_addr, :ai_canonname, :ai_next)
      end

      class Linger < Rubinius::FFI::Struct
        config("rbx.platform.linger", :l_onoff, :l_linger)
      end

      class Ifaddrs < Rubinius::FFI::Struct
        config(
          "rbx.platform.ifaddrs",
          :ifa_next, :ifa_name, :ifa_flags, :ifa_addr, :ifa_netmask
        )
      end

      class Sockaddr < Rubinius::FFI::Struct
        config("rbx.platform.sockaddr", :sa_data, :sa_family)
      end

      class Sockaddr_In < Rubinius::FFI::Struct
        config("rbx.platform.sockaddr_in", :sin_family, :sin_port, :sin_addr, :sin_zero)

        def initialize(sockaddrin)
          @p = Rubinius::FFI::MemoryPointer.new sockaddrin.bytesize
          @p.write_string(sockaddrin, sockaddrin.bytesize)
          super(@p)
        end

        def to_s
          @p.read_string(@p.total)
        end
      end

      class Sockaddr_In6 < Rubinius::FFI::Struct
        config(
          "rbx.platform.sockaddr_in6",
          :sin6_family, :sin6_port, :sin6_flowinfo, :sin6_addr, :sin6_scope_id
        )
      end

      # If we have the details to support unix sockets, do so.
      if Rubinius::FFI.config("sockaddr_un.sun_family.offset") and ::Socket::Constants.const_defined?(:AF_UNIX)
        class Sockaddr_Un < Rubinius::FFI::Struct
          config("rbx.platform.sockaddr_un", :sun_family, :sun_path)

          def initialize(filename = nil)
            maxfnsize = self.size - (Rubinius::FFI.config("sockaddr_un.sun_family.size") + 1)

            if filename and filename.length > maxfnsize
              raise ArgumentError, "too long unix socket path (max: #{maxfnsize}bytes)"
            end
            @p = Rubinius::FFI::MemoryPointer.new self.size
            if filename
              @p.write_string( [::Socket::AF_UNIX].pack("s") + filename )
            end
            super @p
          end

          def to_s
            @p.read_string self.size
          end
        end
      end

      attach_function :_bind,    "bind", [:int, :pointer, :socklen_t], :int
      attach_function :_connect, "connect", [:int, :pointer, :socklen_t], :int

      attach_function :accept,   [:int, :pointer, :pointer], :int
      attach_function :close,    [:int], :int
      attach_function :shutdown, [:int, :int], :int
      attach_function :listen,   [:int, :int], :int
      attach_function :socket,   [:int, :int, :int], :int
      attach_function :send,     [:int, :pointer, :size_t, :int], :ssize_t
      attach_function :recv,     [:int, :pointer, :size_t, :int], :ssize_t
      attach_function :recvfrom, [:int, :pointer, :size_t, :int,
                                  :pointer, :pointer], :int

      attach_function :_getsockopt,
                      "getsockopt", [:int, :int, :int, :pointer, :pointer], :int
      attach_function :_getaddrinfo,
                      "getaddrinfo", [:string, :string, :pointer, :pointer], :int

      attach_function :gai_strerror,  [:int], :string
      attach_function :setsockopt,    [:int, :int, :int, :pointer, :socklen_t], :int
      attach_function :freeaddrinfo,  [:pointer], :void
      attach_function :_getpeername,  "getpeername", [:int, :pointer, :pointer], :int
      attach_function :_getsockname,  "getsockname", [:int, :pointer, :pointer], :int

      attach_function :socketpair,    [:int, :int, :int, :pointer], :int

      attach_function :gethostname,   [:pointer, :size_t], :int
      attach_function :getservbyname, [:pointer, :pointer], :pointer

      attach_function :htons,         [:uint16_t], :uint16_t
      attach_function :ntohs,         [:uint16_t], :uint16_t

      attach_function :_getnameinfo,
                      "getnameinfo", [:pointer, :socklen_t, :pointer, :socklen_t,
                                      :pointer, :socklen_t, :int], :int

      attach_function :getifaddrs, [:pointer], :int
      attach_function :freeifaddrs, [:pointer], :void

      def self.bind(descriptor, sockaddr)
        Rubinius::FFI::MemoryPointer.new :char, sockaddr.bytesize do |sockaddr_p|
          sockaddr_p.write_string sockaddr, sockaddr.bytesize

          _bind descriptor, sockaddr_p, sockaddr.bytesize
        end
      end

      def self.connect(descriptor, sockaddr)
        err = 0
        Rubinius::FFI::MemoryPointer.new :char, sockaddr.bytesize do |sockaddr_p|
          sockaddr_p.write_string sockaddr, sockaddr.bytesize

          err = _connect descriptor, sockaddr_p, sockaddr.bytesize
        end

        err
      end

      def self.getsockopt(descriptor, level, optname)
        Rubinius::FFI::MemoryPointer.new 256 do |val| # HACK magic number
          Rubinius::FFI::MemoryPointer.new :socklen_t do |length|
            length.write_int 256 # HACK magic number

            err = _getsockopt descriptor, level, optname, val, length

            Errno.handle "Unable to get socket option" unless err == 0

            return val.read_string(length.read_int)
          end
        end
      end

      def self.getaddrinfo(host, service = nil, family = nil, socktype = nil,  protocol = nil, flags = nil)
        hints = Addrinfo.new
        hints[:ai_family] = family || 0
        hints[:ai_socktype] = socktype || 0
        hints[:ai_protocol] = protocol || 0
        hints[:ai_flags] = flags || 0

        if host && (host.empty? || host == '<any>')
          host = "0.0.0.0"
        elsif host == '<broadcast>'
          host = '255.255.255.255'
        end

        res_p = Rubinius::FFI::MemoryPointer.new :pointer

        err = _getaddrinfo host, service, hints.pointer, res_p

        raise SocketError, gai_strerror(err) unless err == 0

        ptr = res_p.read_pointer

        return [] unless ptr

        res = Addrinfo.new ptr

        addrinfos = []

        while true
          addrinfo = []
          addrinfo << res[:ai_flags]
          addrinfo << res[:ai_family]
          addrinfo << res[:ai_socktype]
          addrinfo << res[:ai_protocol]
          addrinfo << res[:ai_addr].read_string(res[:ai_addrlen])
          addrinfo << res[:ai_canonname]

          addrinfos << addrinfo

          break unless res[:ai_next]

          res = Addrinfo.new res[:ai_next]
        end

        return addrinfos
      ensure
        hints.free if hints

        if res_p
          ptr = res_p.read_pointer

          # Be sure to feed a legit pointer to freeaddrinfo
          if ptr and !ptr.null?
            freeaddrinfo ptr
          end
          res_p.free
        end
      end

      def self.getaddress(host)
        addrinfos = getaddrinfo(host)
        unpack_sockaddr_in(addrinfos.first[4], false).first
      end

      def self.getnameinfo(sockaddr, flags = ::Socket::Constants::NI_NUMERICHOST | ::Socket::Constants::NI_NUMERICSERV,
                           reverse_lookup = !BasicSocket.do_not_reverse_lookup)
        name_info = []
        value = nil

        Rubinius::FFI::MemoryPointer.new :char, sockaddr.bytesize do |sockaddr_p|
          Rubinius::FFI::MemoryPointer.new :char, ::Socket::Constants::NI_MAXHOST do |node|
            Rubinius::FFI::MemoryPointer.new :char, ::Socket::Constants::NI_MAXSERV do |service|
              sockaddr_p.write_string sockaddr, sockaddr.bytesize

              if reverse_lookup then
                err = _getnameinfo(sockaddr_p, sockaddr.bytesize,
                                   node, ::Socket::Constants::NI_MAXHOST, nil, 0, 0)

                name_info[2] = node.read_string if err == 0
              end

              err = _getnameinfo(sockaddr_p, sockaddr.bytesize,
                                 node, ::Socket::Constants::NI_MAXHOST,
                                 service, ::Socket::Constants::NI_MAXSERV,
                                 flags)

              unless err == 0 then
                raise SocketError, gai_strerror(err)
              end

              sa_family = Sockaddr_In.new(sockaddr)[:sin_family]

              name_info[0] = ::Socket::Constants::AF_TO_FAMILY[sa_family]
              name_info[1] = service.read_string
              name_info[3] = node.read_string
            end
          end
        end

        name_info[2] = name_info[3] if name_info[2].nil?
        name_info
      end

      def self.getpeername(descriptor)
        Rubinius::FFI::MemoryPointer.new :char, 128 do |sockaddr_storage_p|
          Rubinius::FFI::MemoryPointer.new :socklen_t do |len_p|
            len_p.write_int 128

            err = _getpeername descriptor, sockaddr_storage_p, len_p

            Errno.handle 'getpeername(2)' unless err == 0

            sockaddr_storage_p.read_string len_p.read_int
          end
        end
      end

      def self.getsockname(descriptor)
        Rubinius::FFI::MemoryPointer.new :char, 128 do |sockaddr_storage_p|
          Rubinius::FFI::MemoryPointer.new :socklen_t do |len_p|
            len_p.write_int 128

            err = _getsockname descriptor, sockaddr_storage_p, len_p

            Errno.handle 'getsockname(2)' unless err == 0

            sockaddr_storage_p.read_string len_p.read_int
          end
        end
      end

      def self.pack_sockaddr_in(host, port, family, type, flags)
        hints = Addrinfo.new
        hints[:ai_family] = family
        hints[:ai_socktype] = type
        hints[:ai_flags] = flags

        if host && host.empty?
          host = "0.0.0.0"
        end

        res_p = Rubinius::FFI::MemoryPointer.new :pointer

        err = _getaddrinfo host, port.to_s, hints.pointer, res_p

        raise SocketError, gai_strerror(err) unless err == 0

        return [] if res_p.read_pointer.null?

        res = Addrinfo.new res_p.read_pointer

        return res[:ai_addr].read_string(res[:ai_addrlen])

      ensure
        hints.free if hints

        if res_p then
          ptr = res_p.read_pointer

          freeaddrinfo ptr if ptr and not ptr.null?

          res_p.free
        end
      end

      def self.unpack_sockaddr_in(sockaddr, reverse_lookup)
        family, port, host, ip = getnameinfo(
          sockaddr,
          ::Socket::Constants::NI_NUMERICHOST | ::Socket::Constants::NI_NUMERICSERV,
          reverse_lookup
        )

        # On some systems this doesn't fail for families other than AF_INET(6)
        # so we raise manually here.
        unless family =~ /AF_INET/
          raise ArgumentError, 'not an AF_INET/AF_INET6 sockaddr'
        end

        return host, ip, port.to_i
      end
    end
  end
end
