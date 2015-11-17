unit class IPerl6;

use Digest::HMAC;
use Digest::SHA;
use JSON::Fast;
use Net::ZMQ;
use Net::ZMQ::Constants;
use Net::ZMQ::Poll;

has Net::ZMQ::Context $!ctx;
has $!transport;
has $!ip;
has $!key;
submethod BUILD(:%connection) {
    $!ctx .= new;
    $!transport = %connection<transport>;
    $!ip = %connection<ip>;
    $!key = %connection<key>;

    self!setup_sockets(%connection);
    self!setup_heartbeat(%connection);
}

has Net::ZMQ::Socket $!shell;
has Net::ZMQ::Socket $!iopub;
has Net::ZMQ::Socket $!stdin;
has Net::ZMQ::Socket $!control;
method !setup_sockets(%connection) {
    say "# Setting up sockets...";
    $!shell   = self!socket: ZMQ_ROUTER, %connection<shell_port>;
    $!iopub   = self!socket: ZMQ_PUB,    %connection<iopub_port>;
    $!stdin   = self!socket: ZMQ_ROUTER, %connection<stdin_port>;
    $!control = self!socket: ZMQ_ROUTER, %connection<control_port>;
}

method !socket($type, $port) {
    my Net::ZMQ::Socket $s .= new: $!ctx, $type;
    my $addr = self!make_address: $port;
    $s.bind: $addr;
    return $s;
}

#has Thread $!hb_thread;
has Net::ZMQ::Socket $!hb_socket;
method !setup_heartbeat(%connection) {
    $!hb_socket = self!socket: ZMQ_ROUTER, %connection<hb_port>;

    # There's a bug on Rakudo/Moar where running the heartbeat in a separate
    # thread hangs the program. So for the time being we interleave things.
    # Not optimal, but at least it gets us something that works (mostly).
    #my $hb_addr = self!make_address: %connection<hb_port>;
    #$!hb_thread .= start: {
    #    my Net::ZMQ::Context $ctx .= new;
    #    my Net::ZMQ::Socket $s .= new: $ctx, ZMQ_ROUTER;
    #    # XXX: The IPython base kernel code sets linger 1000 on the socket.
    #    # Maybe we want that too?
    #    $s.bind: $hb_addr;
    #    loop {
    #        my $ret = device($s, $s, :queue);
    #        last if $ret != 4; # XXX: 4 is the value of EINTR. On my machine anyways...
    #    }
    #};
}

method !make_address($port) {
    my $sep = $!transport eq "tcp" ?? ":" !! "-";
    return "$!transport://$!ip$sep$port";
}

method start() {
    # There are two things making the main run loop here weirder than
    # necessary. First is the hang bug described in !setup heartbeat; thus we
    # do a blocking poll on the heartbeat to make sure we reply to heartbeat
    # requests, and between each heartbeat poll we make non-blocking polls on
    # the other sockets. This means we should work fairly well, as long as
    # users don't start computations that take *too* long.
    #
    # Second is a limitation in Net::ZMQ (due in turn to a limitation in
    # NativeCall), where we can only poll single sockets at a time, not all of
    # them at once. Thus we have to cascade the polls, one after the other.
    my $i = 0;
    loop {
        say "# Polling hearbeat ($i)...";
        if poll_one($!hb_socket, 500_000, :in) {
            say "# Heart beating";
            $!hb_socket.send: $!hb_socket.receive(0);
        }
        if poll_one($!shell, 0, :in) {
            say "# Message on shell:";
            self!read_message: $!shell;
        }
        if poll_one($!control, 0, :in) {
            say "# Message on control:";
            self!read_message: $!control;
        }
        if poll_one($!iopub, 0, :in) {
            say "# Message on iopub:";
            self!read_message: $!iopub;
        }
        if poll_one($!stdin, 0, :in) {
            say "# Message on stdin:";
            self!read_message: $!stdin;
        }
        $i++
    }
}

method !read_message(Net::ZMQ::Socket $s) {
    my buf8 @routing;
    my buf8 @message;
    my $separated = False;

    # A message from the IPython frontend is sent in several parts. First is a
    # sequence of socket ids for the originating sockets; several because ZMQ
    # supports routing messages over many sockets. Next is the "<IDS|MSG>"
    # separator to signal the start of the IPython part of the message.
    #
    # The IPython message consists of a HMAC, a header, a parent header,
    # metadata, a message body, and possibly some additional data blobs; in
    # that order.
    loop {
        my buf8 $data = $s.receive.data;

        if not $separated and not $data eqv $separator { @routing.push: $data }
        elsif not $separated and $data eqv $separator  {
            $separated = True;
            next;
        }
        else { @message.push: $data }

        last if not $s.getopt: ZMQ_RCVMORE;
    }

    say "# routing={+@routing}; message={+@message}";
    my $hmac = hmac-hex $!key, @message[1] ~ @message[2] ~ @message[3] ~ @message[4], &sha256;
    die "HMAC verification failed!" if $hmac ne @message.shift.decode;

    my $header   = from-json @message.shift.decode;
    my $parent   = from-json @message.shift.decode;
    my $metadata = from-json @message.shift.decode;
    my $content  = from-json @message.shift.decode;

    return {ids => @routing, header => $header, parent => $parent,
        metadata => $metadata, content => $content, extra_data => @message};
}

sub MAIN(Str $connection) is export {
    my IPerl6 $kernel .= new: connection => from-json($connection.IO.slurp);
    $kernel.start;
}
