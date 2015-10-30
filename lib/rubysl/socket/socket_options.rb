module RubySL
  module Socket
    module SocketOptions
      def self.socket_level(level, family = nil)
        case level
        when Symbol, String
          if ::Socket.const_defined?(level)
            ::Socket.const_get(level)
          else
            if family and is_ip_family?(family)
              ip_level_to_int(level)
            else
              constant("SOL", level)
            end
          end
        else
          level
        end
      end

      def self.socket_option(level, optname)
        case optname
        when Symbol, String
          if ::Socket.const_defined?(optname)
            ::Socket.const_get(optname)
          else
            case level
            when ::Socket::SOL_SOCKET
              constant("SO", optname)
            when ::Socket::SOL_IP
              constant("IP", optname)
            when ::Socket::SOL_TCP
              constant("TCP", optname)
            when ::Socket::SOL_UDP
              constant("UDP", optname)
            else
              if ::Socket.const_defined?(:IPPROTO_IPV6) &&
                level == ::Socket::IPPROTO_IPV6
                constant("IPV6", optname)
              else
                raise SocketError,
                  "Unsupported socket level option name: #{optname}"
              end
            end
          end
        else
          optname
        end
      end

      def self.is_ip_family?(family)
        family == "AF_INET" || family == "AF_INET6"
      end

      def self.ip_level_to_int(level)
        prefixes = ["IPPROTO", "SOL"]

        prefixes.each do |prefix|
          const = "#{prefix}_#{level}"

          if ::Socket.const_defined?(const)
            return ::Socket.const_get(const)
          end
        end

        nil
      end

      def self.constant(prefix, suffix)
        const = "#{prefix}_#{suffix}"

        if ::Socket.const_defined?(const)
          ::Socket.const_get(const)
        else
          raise SocketError, "Undefined socket constant: #{const}"
        end
      end
    end
  end
end
