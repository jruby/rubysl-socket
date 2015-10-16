require File.expand_path('../../fixtures/classes', __FILE__)

describe "Socket#listen" do
  before do
    @socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
  end

  after do
    @socket.closed?.should be_false
    @socket.close
  end

  it "verifies we can listen for incoming connections" do
    sockaddr = Socket.pack_sockaddr_in(SocketSpecs.port, "127.0.0.1")

    @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    @socket.bind(sockaddr)
    @socket.listen(1).should == 0
  end
end
