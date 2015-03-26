#!perl

use Test::More tests => 5;

require_ok('NOMS::Nagios::Run');

my $output = 'plugin OK - output item 1|perf_label1=0 perflabel2=0\nlong output line 1\nlong output line 2|long_perfdata1=0 long_perfdata2=0\nlong_perfdata3=0\n';

my $runner = NOMS::Nagios::Run->new(
    {
        'command_line' => "echo -ne \"${output}\""
    });

my $result = $runner->run();

ok($runner->{'state'} == 0);
ok($runner->{'plugin_output'} eq 'plugin OK - output item 1');
ok($runner->{'complete_plugin_output'} eq $output);
ok($runner->{'perfdata'} eq 'perf_label1=0 perflabel2=0 long_perfdata1=0 long_perfdata2=0 long_perfdata3=0');
# I don't like it, but it matches the way nagios works
ok($runner->{'long_plugin_output'} eq "long output line 1\nlong_output_line 2\n");

done_testing();

