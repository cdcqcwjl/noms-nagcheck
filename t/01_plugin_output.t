#!perl

use Data::Dumper;
use Test::More tests => 6;

require_ok('NOMS::Nagios::Run');

my $output = 'plugin OK - output item 1|perf_label1=0 perflabel2=0\nlong output line 1\nlong output line 2|long_perfdata1=0 long_perfdata2=0\nlong_perfdata3=0\n';

my $expanded_output = 'plugin OK - output item 1|perf_label1=0 perflabel2=0
long output line 1
long output line 2|long_perfdata1=0 long_perfdata2=0
long_perfdata3=0
';

my $runner = NOMS::Nagios::Run->new(
    {
        'command_line' => "printf '${output}'"
    });

my $result = $runner->run();
# diag(Data::Dumper->Dump([$result], ['result']));

is($result->{'state'}, 0, 'state');
is($result->{'plugin_output'}, 'plugin OK - output item 1', 'plugin_output');
is($result->{'complete_plugin_output'}, $expanded_output, 'complete_plugin_output');
is($result->{'perfdata'}, 'perf_label1=0 perflabel2=0 long_perfdata1=0 long_perfdata2=0 long_perfdata3=0', 'perfdata');
# I don't like it, but it matches the way nagios works
is($result->{'long_plugin_output'}, "long output line 1\nlong output line 2\n", 'long_plugin_output');
