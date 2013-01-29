use Panda::Common;
use Panda::Builder;

my $nqp        = 'nqp';
my $parrot     = 'parrot';
my $pbc_to_exe = 'pbc_to_exe';
my $executable = $*OS eq 'MSWin32' ?? 'iperl6_kernel.exe' !! 'iperl6_kernel';

class Build is Panda::Builder {
    method build(Pies::Project $p) {
        my $workdir = $.resources.workdir($p);

        shell "$nqp --vmlibs=perl6_group,perl6_ops --target=pir "
            ~ "--output=iperl6_kernel.pir bin/iperl6_kernel.nqp";
        shell "$parrot -o iperl6_kernel.pbc iperl6_kernel.pir";
        shell "$pbc_to_exe --output=bin/$executable iperl6_kernel.pbc"
    }
}
