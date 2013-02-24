# vi: ft=perl6

use Perl6::Compiler;
use Perl6::Actions;

# pass on some handler object that allows interfacing
# with the ZMQ wrapper
class ProtocolGetter {
    has $!proto;

    method set($foo) {
        nqp::say("setting protocol instance");
        $*W.add_object($foo);
        $!proto := $foo;
    }

    method protocol() {
        $!proto;
    }
};

class ChattyRepl is Perl6::Compiler {
    method interactive(*%adverbs) {
        # copied 1:1 from HLL::Compiler {{{
        # blank_context() serves as a cumulative "outer context"
        # for code executed in this interactive REPL instance.
        # It's invoked once to obtain a context, and the LexPad
        # of that context is replaced with an empty Hash that
        # we can use to cumulatively store lexicals.
        sub blank_context() {
            # transform context's pad into a Hash
            my %blank_pad;
            pir::copy__vPP(
                pir::getattribute__PPs(pir::getinterp__P(){'context'}, 'lex_pad'),
                %blank_pad);
            pir::getinterp__P(){'context'};
        }
        &blank_context.set_outer(nqp::null());
        my $interactive_ctx := blank_context();
        my %interactive_pad := 
            pir::getattribute__PPs($interactive_ctx, 'lex_pad');

        my $target := nqp::lc(%adverbs<target>);

        pir::getinterp__P().stderr_handle().print(self.interactive_banner);

        my $stdin    := pir::getinterp__P().stdin_handle();
        my $encoding := ~%adverbs<encoding>;
        if $encoding && $encoding ne 'fixed_8' {
            $stdin.encoding($encoding);
        }

        my $save_ctx;
        while 1 {
            last unless $stdin;

            #my $code := $stdin.readline_interactive(~$prompt);
            my $result := $*ZMQ_PROTOCOL.protocol.get_command();
            my $command := $result.shift;
            my $code := $result.shift;
            my $callback := $result.shift;

            last if nqp::isnull($code);
            unless nqp::defined($code) {
                nqp::print("\n");
                last;
            }

            # Set the current position of stdout for autoprinting control
            #my $*AUTOPRINTPOS := (pir::getinterp__P()).stdout_handle().tell();
            my $*CTXSAVE := self;
            my $*MAIN_CTX;

            my $pretty-out := "";
            if $code {
                $code := $code ~ "\n";
                my $output;
                {
                    $output := self.eval($code, :outer_ctx($save_ctx), |%adverbs);
                    CATCH {
                        nqp::print(~$! ~ "\n");
                        next;
                    }
                };
                if nqp::defined($*MAIN_CTX) {
                    my $cur_ctx := $*MAIN_CTX;
                    my %seen;
                    until nqp::isnull($cur_ctx) {
                        my $pad := nqp::ctxlexpad($cur_ctx);
                        unless nqp::isnull($pad) {
                            for $pad {
                                my str $key := ~$_;
                                unless nqp::existskey(%seen, $key) {
                                    %interactive_pad{$key} := nqp::atkey($pad, $key);
                                    %seen{$key} := 1;
                                }
                            }
                        }
                        $cur_ctx := nqp::ctxouter($cur_ctx);
                    }
                    $save_ctx := $interactive_ctx;
                }

                if !nqp::isnull($output) && nqp::can($output, 'dump') {
                    $pretty-out := ($output.dump());
                }
            }
            $callback($pretty-out, "", "");
        }
    }
}

sub hll-config($config) {
    $config<name>           := 'rakudo';
    $config<version>        := '';
    $config<release-number> := '';
    $config<codename>       := '';
    $config<build-date>     := '2013-02-24T16:57:45Z';
}

sub MAIN(@ARGS) {
    #copied from jnthn/rakudo-debugger

    # initialize dynops
    pir::rakudo_dynop_setup__v();

    # bump up the recursion limit
    pir::getinterp__P().recursion_limit(100000);

    # create and configure a compiler object
    my $comp := ChattyRepl.new();
    $comp.language('perl6');
    $comp.parsegrammar(Perl6::Grammar);
    $comp.parseactions(Perl6::Actions);
    $comp.addstage('syntaxcheck', :before<past>);
    $comp.addstage('optimize', :before<post>);
    hll-config($comp.config);
    my $COMPILER_CONFIG := $comp.config;

    # add extra commandline options
    my @clo := $comp.commandline_options();
    @clo.push('setting=s');
    @clo.push('c');
    @clo.push('I=s');
    @clo.push('M=s');

    # Set up module loading trace
    my @*MODULES := [];
    
    # Set up END block list, which we'll run at exit.
    my @*END_PHASERS := [];
    
    # Force loading of the debugger module.
    my $pname := @ARGS.shift();
    @ARGS.unshift('-Ilib');
    @ARGS.unshift('-MIPerl6::ZMQ');
    @ARGS.unshift($pname);

    my $*ZMQ_PROTOCOL := ProtocolGetter.new();

    # Enter the compiler.
    $comp.command_line(@ARGS, :encoding('utf8'), :transcode('ascii iso-8859-1'));

    # Run any END blocks before exiting.
    for @*END_PHASERS { $_() }
}
