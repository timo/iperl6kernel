module IPerl6::ZMQ;

say "i'm being run!";

$*ZMQ_PROTOCOL.set(IPerl6::ZMQ::Protocol.new());

use JSON::Tiny;
use Net::ZMQ;
use Net::ZMQ::Constants;

my Net::ZMQ::Context $zmqctx .= new;
my Net::ZMQ::Socket $pubsock .= new($zmqctx, ZMQ_PUB);
my Net::ZMQ::Socket $shellsock .= new($zmqctx, ZMQ_ROUTER);
my Net::ZMQ::Socket $stdinsock .= new($zmqctx, ZMQ_ROUTER);

$pubsock.bind:   "tcp://*:5551";
$shellsock.bind: "tcp://*:5552";
$stdinsock.bind: "tcp://*:5553";

my \DELIM := "<IDS|MSG>";

my class Stdin {
    has $.protocol;

    method read($num) {
        return substr("reading currently unsupported", 0, $num);
    }
}

multi send-zmq($data, :$SNDMORE?, :$PUBLISH?) {
    state @send-buf;
    push @send-buf, $data;
    unless $SNDMORE {
        my Str $result = to-json(@send-buf);
        $*ZMQOUT.write($result.bytes ~ "\n");
        $*ZMQOUT.write($result);
        @send-buf = [];
    }
}

multi send-zmq(@data-parts) {
    send-zmq($_, :SNDMORE) for @data-parts[0..*-2];
    send-zmq($_) for @data-parts[*-1];
}

sub recv-zmq($socket --> List) {
    my @res;
    @res.push($socket.recv);
    while $socket.getsockopt(ZMQ_RCVMORE) {
        @res.push($socket.recv);
    }
    return @res;
}

my class Message {
    has $.id;
    has $.parent-header;
    has $.header;
    has $.content;
    has $.msg-id;
    has $.msg-type;
    has $.hmac;

    submethod recv(--> Message) {
        my $data = recv-zmq($shellsock);
        my $id = $data.shift;
        die "did not find a delimiter after 1 id" if $data.shift ne DELIM;
        my &d = { $data.shift };
        return Message.new(
            :$id,
            :hmac(d),
            :header(d),
            :parent_header(d),
            :content(d));
    }

    method answer returns Message {
        return Message.new(:id($.id), :parent-header($.header));
    }

    method sign returns Str {
        ""
    }

    method verify returns Bool {
        True;
    }

    method send {
        $!header<date> = DateTime.now().Str;
        $!header<msg-id> = q:x{uuidgen};
        send-zmq([$.id, DELIM, self.sign, $.header, $.parent-header, $.content]);
    }
}

our class IPerl6::ZMQ::Protocol {
    has $.username = "camilla";
    has $.session = q:x{uuidgen};
    has $.ident = q:x{uuidgen};

    has $.IN;
    has $.OUT;

    method BUILD {
        $.session = q:x{uuidgen}.trim;
        $.ident = q:x{uuidgen}.trim;
    }

    method bind(Message $msg) {
        $msg.header<username> = $.username;
        $msg.header<session> = $.session;
    }

    method get_command {
        say "going to receive a command now";
        my $msg = Message.recv;
        given my $msgtype = $msg.header<msg_type> {
            when "execute_request" {
                say "going to do an execute request";
                sub exec_req_cb ($result, $stdout, $stderr) {
                    say "i've done it!";
                }
                return ($msgtype, $msg.content<code>, &exec_req_cb);
            }
        }
    }
}

