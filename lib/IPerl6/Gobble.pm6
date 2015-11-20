unit class IPerl6::Gobble;

my $nl = "\n";
has $!output = "";

method print(Str $data --> True) { $!output ~= $data }
method put(Str $data --> True)   { $!output ~= $data ~ $nl }
method print-nl(--> True)       { $!output ~= $nl }

method get-output() {
    my $data = $!output;
    $!output = "";
    return $data;
}

# Reading from STDIN NYI.
method get()        { die "IPerl6::Gobble.read NYI" }
method read()       { die "IPerl6::Gobble.read NYI" }
method readchars()  { die "IPerl6::Gobble.readchars NYI" }
method slurp-rest() { die "IPerl6::Gobble.read NYI" }
