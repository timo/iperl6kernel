use nqp;
use Inline::Python;

my $program = q:to<PYTHON>;
from ipykernel.kernelapp import IPKernelApp
from ipykernel.kernelbase import Kernel

executor = None

class Perl6Kernel (Kernel):
    implementation = 'python-perl6'
    implementation_version = '0.1'
    language = 'Perl'
    language_version = '6'
    banner = 'Welcome to the gloriously hacky Perl 6 kernel!'

    def do_execute(self, code, silent, store_history=True, user_expressions=None, allow_stdin=False):
        global executor
        if not silent:
            stream_content = {'name': 'stdout', 'text': executor(code)}
            self.send_response(self.iopub_socket, 'stream', stream_content)

        return {'status': 'ok',
                'execution_count': self.execution_count,
                'payload': [],
                'user_expressions': {}}

def run(e, connection):
    #print "Running..."
    global executor
    #print "Setting executor..."
    executor = e
    #print "Starting..."
    IPKernelApp.launch_instance(kernel_class=Perl6Kernel, connection_file=connection)
PYTHON

my $save_ctx := nqp::null();
my $compiler := nqp::getcomp('perl6');
sub executor($code) {
    my $*CTXSAVE := $compiler;
    my $*MAIN_CTX;

    my $output;
    {
        CATCH { return "SHENANIGANS!" } # TODO: Error handling.
        $output := $compiler.eval($code, :outer_ctx($save_ctx));
    }

    if nqp::defined($*MAIN_CTX) { $save_ctx := $*MAIN_CTX }
    ~$output;
}
#sub executor($code) { $code }

# XXX: For some reason, this results in an ambiguous multidispatch inside
# Inline::Python...
#sub MAIN(Str $connection) {
#    my Inline::Python $python .= new;
#    $python.run: $program;
#    $python.call('__main__', 'run', &executor, $connection)
#}

my Inline::Python $python .= new;
$python.run: $program;
$python.call: '__main__', 'run', sub ($code) { executor($code) }, @*ARGS[0]
