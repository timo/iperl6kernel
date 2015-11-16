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
    my $ids = $s.receive.data.decode;
    my $delim = $s.receive.data.decode;
    my $hmac = $s.receive.data.decode;
    my $raw_header   = $s.receive.data;
    my $raw_parent   = $s.receive.data;
    my $raw_metadata = $s.receive.data;
    my $raw_content  = $s.receive.data;

    my $verify = hmac-hex $!key, $raw_header ~ $raw_parent ~ $raw_metadata ~ $raw_content, &sha256;

    my $header   = from-json $raw_header.decode;
    my $parent   = from-json $raw_parent.decode;
    my $metadata = from-json $raw_metadata.decode;
    my $content  = from-json $raw_content.decode;
    say to-json({ids => $ids, hmac => $hmac eq $verify ?? "ok" !! "BAD", header => $header, parent => $parent,
        metadata => $metadata, content => $content});
}

sub MAIN(Str $connection) is export {
    my IPerl6 $kernel .= new: connection => from-json($connection.IO.slurp);
    $kernel.start;
}
