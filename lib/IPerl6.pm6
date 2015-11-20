unit class IPerl6;

use nqp;

use Digest::HMAC;
use Digest::SHA;
use JSON::Fast;
use Net::ZMQ;
use Net::ZMQ::Constants;
use Net::ZMQ::Poll;
use UUID;

use IPerl6::Gobble;

has Net::ZMQ::Context $!ctx;
has $!transport;
has $!ip;
has $!key;
has $!session = ~UUID.new: :version(4);
has $!stdout  = IPerl6::Gobble.new;
has $!stderr  = IPerl6::Gobble.new;
has $!exec_counter = 1;
has @!history = ();
submethod BUILD(:%connection) {
    $!ctx .= new;
    $!transport = %connection<transport>;
    $!ip = %connection<ip>;
    $!key = %connection<key>;

    self!setup_sockets(%connection);
    self!setup_heartbeat(%connection);
    self!setup_compiler;
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

    self!starting;
}

method !socket($type, $port) {
    my Net::ZMQ::Socket $s .= new: $!ctx, $type;
    my $addr = self!make_address: $port;
    $s.bind: $addr;
    return $s;
}

has $!save_ctx;
has $!compiler;
method !setup_compiler() {
    $!save_ctx := nqp::null();
    $!compiler := nqp::getcomp('perl6');
}

#has Thread $!hb_thread;
has Net::ZMQ::Socket $!hb_socket;
method !setup_heartbeat(%connection) {
    $!hb_socket = self!socket: ZMQ_REP, %connection<hb_port>;
    #$!hb_socket = self!socket: ZMQ_ROUTER, %connection<hb_port>;

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
        if poll_one($!hb_socket, 500_000, :in) {
            $!hb_socket.send: $!hb_socket.receive;
        }
        if poll_one($!shell, 0, :in) {
            self!shell_message
        }
        if poll_one($!control, 0, :in) {
            say "# Message on control:";
            say self!read_message: $!control;
        }
        if poll_one($!iopub, 0, :in) {
            say "# Message on iopub:";
            say self!read_message: $!iopub;
        }
        if poll_one($!stdin, 0, :in) {
            say "# Message on stdin:";
            say self!read_message: $!stdin;
        }
        $i++
    }
}

method !shell_message() {
    my $message = self!read_message: $!shell;
    say "# Message on shell: $message<header><msg_type>";
    given $message<header><msg_type> {
        when 'kernel_info_request' {
            my $reply = {
                protocol_version => '5.0',
                implementation => 'IPerl6',
                implementation_version => '0.0.1',
                language_info => {
                    name => 'perl6',
                    version => '0.1.0',
                    mimetype => 'text/plain',
                    file_extension => '.p6',
                },
                banner => 'Welcome to IPerl6!',
            };
            self!send: $!shell, $reply, type => 'kernel_info_reply', parent => $message
        }
        when 'history_request' {
            self!history_request: $message;
        }
        when 'execute_request' {
            self!execute: $message;
        }
        default { die "Unknown message type: {to-json $message<header>}\n{to-json $message<content>}" }
    }
}

method !history_request($message) {
    # XXX: Since we haven't actually implemented execution yet, we can just
    # cheat here and always send back an empty history list.
    self!send: $!shell, {history => []}, type => 'history_reply', parent => $message;
}

method !execute($message) {
    my $code = $message<content><code>;
    my $*CTXSAVE := $!compiler;
    my $*MAIN_CTX;

    # TODO: Handle silent, store_history and user_expressions parameters
    # TODO: Rebroadcast code input on the IOpub socket (looking at the
    # ipykernel/kernelbase.py code, looks like it should have the original
    # request as its parent).

    @!history.push: $code;

    my $result;
    say "# Executing `$code'";
    self!busy;
    {
        CATCH { say "SHENANIGANS!" }
        my $*OUT = $!stdout;
        my $*ERR = $!stderr;
        $result := $!compiler.eval($code, :outer_ctx($!save_ctx));
    }

    if nqp::defined($*MAIN_CTX) { $!save_ctx := $*MAIN_CTX }

    say $result;

    self!send: $!shell, {status => 'ok', execution_count => $!exec_counter},
        type => 'execute_reply', parent => $message;

    self!flush_output: $!stdout, 'stdout', $message;
    self!flush_output: $!stderr, 'stderr', $message;

    self!send: $!iopub, {execution_count => $!exec_counter, data => {'text/plain' => $result.gist}},
        type => 'execute_result', parent => $message;
    self!idle;
    $!exec_counter++;
}

method !flush_output($stream, $name, $parent) {
    my $output = $stream.get-output;
    self!send($!iopub, {:$name, text => $output}, type => 'stream', :$parent)
        if $output;
}

method !starting() {
    self!send: $!iopub, {execution_state => 'starting'}, type => 'status';
}

method !busy() {
    self!send: $!iopub, {execution_state => 'busy'}, type => 'status';
}

method !idle() {
    self!send: $!iopub, {execution_state => 'idle'}, type => 'status';
}

# Str.encode returns a Blob[unit8], whereas we want a Buf[uint8] in the eqv
# check below, so we have to construct the appropriate thing by hand here.
my buf8 $separator = buf8.new: "<IDS|MSG>".encode;
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

    my $hmac = hmac-hex $!key, @message[1] ~ @message[2] ~ @message[3] ~ @message[4], &sha256;
    die "HMAC verification failed!" if $hmac ne @message.shift.decode;

    my $header   = from-json @message.shift.decode;
    my $parent   = from-json @message.shift.decode;
    my $metadata = from-json @message.shift.decode;
    my $content  = from-json @message.shift.decode;

    #say to-json $header;

    return {ids => @routing, header => $header, parent => $parent,
        metadata => $metadata, content => $content, extra_data => @message};
}

method !send($socket, $message, :$type!, :$parent = {}) {
    say "# Sending ($type)";

    if $parent {
        for $parent<ids>.list {
            $socket.send($_, ZMQ_SNDMORE);
        }
    }
    $socket.send: "<IDS|MSG>", ZMQ_SNDMORE;

    #say(to-json $message);# if $type eq 'execute_result';

    my $header = {
        date => ~DateTime.new(now),
        msg_id => ~UUID.new(:version(4)),
        msg_type => $type,
        session => $!session,
        username => 'bogus', # TODO: Set this correctly.
        version => '5.0',
    };
    my $metadata = {};

    my $header_bytes  = to-json($header).encode;
    my $parent_bytes  = to-json($parent<header>).encode;
    my $meta_bytes    = to-json($metadata).encode;
    my $content_bytes = to-json($message).encode;

    my $hmac = hmac-hex $!key, $header_bytes ~ $parent_bytes ~ $meta_bytes ~ $content_bytes, &sha256;

    $socket.send: $hmac, ZMQ_SNDMORE;
    $socket.send: $header_bytes, ZMQ_SNDMORE;
    $socket.send: $parent_bytes, ZMQ_SNDMORE;
    $socket.send: $meta_bytes, ZMQ_SNDMORE;
    $socket.send: $content_bytes;
}

sub MAIN(Str $connection) is export {
    my IPerl6 $kernel .= new: connection => from-json($connection.IO.slurp);
    $kernel.start;
}
