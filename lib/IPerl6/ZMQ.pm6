module IPerl6::ZMQ;

use JSON::Tiny;

my \DELIM := "<IDS|MSG>";

our class Stdin {
    has $.protocol;

    method read($num) {
        return substr("reading currently unsupported", 0, $num);
    }
}

multi send-zmq($data, :$SNDMORE?) {
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

sub recv-zmq(--> List) {
    my $datlen = $*ZMQIN.get();
    my $data = $*ZMQIN.read($datlen).decode("utf8");
    return from-json($data);
}

class Message {
    has $.id;
    has $.parent-header;
    has $.header;
    has $.content;
    has $.msg-id;
    has $.msg-type;
    has $.hmac;

    submethod recv(--> Message) {
        my $data = recv-zmq;
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

our class Protocol {
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
        my $msg = Message.recv;
    }
}

$*ZMQ_PROTOCOL = Protocol.new();
