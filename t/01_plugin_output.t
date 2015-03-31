#!perl

use Data::Dumper;
use Test::More;

my @fields = qw(state plugin_output complete_plugin_output perfdata long_plugin_output);

my @specs = (
    {   'name' => 'nothing',
        'state' => 0,
        'command' => ':',
        'complete_plugin_output' => '',
        'plugin_output' => '',
        'perfdata' => undef,
        'long_plugin_output' => undef
    },
    {
        'name' => 'simple',
        'state' => 0,
        'complete_plugin_output' => "plugin OK - output\n",
        'perfdata' => undef,
        'plugin_output' => 'plugin OK - output',
        'long_plugin_output' => undef
    },
    {
        'name' => 'crit',
        'command' => "printf 'plugin CRITICAL - error\\n' && exit 2",
        'state' => 2,
        'complete_plugin_output' => "plugin CRITICAL - error\n",
        'perfdata' => undef,
        'plugin_output' => 'plugin CRITICAL - error',
        'long_plugin_output' => undef
    },
    {
        'name' => 'perf',
        'state' => 0,
        'complete_plugin_output' => "plugin OK - output|perflabel1=10s;5;15\n",
        'plugin_output' => 'plugin OK - output',
        'perfdata' => 'perflabel1=10s;5;15',
        'long_plugin_output' => undef
    },
    {
        'name' => 'long',
        'state' => 0,
        'complete_plugin_output' => "plugin OK - output\nlong output 1\n",
        'plugin_output' => 'plugin OK - output',
        'long_plugin_output' => "long output 1\n",
        'perfdata' => undef
    },
    {
        'name' => 'emptyperf',
        'state' => 0,
        'complete_plugin_output' => "plugin OK - output|\n",
        'plugin_output' => 'plugin OK - output',
        'perfdata' => '',
        'long_plugin_output' => undef
    },
    {
        'name' => 'stderr',
        'state' => 0,
        'command' => "printf 'plugin OK - output\\n'; printf 'warning: 1\\nwarning: 2\\n' >&2",
        'complete_plugin_output' => "plugin OK - output\n(stderr) warning: 1\nwarning: 2\n",
        'plugin_output' => 'plugin OK - output',
        'perfdata' => undef,
        'long_plugin_output' => undef
    },
    { 'name' => 'allfields',
      'complete_plugin_output' => "plugin OK - output item 1|perf_label1=0 perflabel2=0\nlong output line 1\nlong output line 2|long_perfdata1=0 long_perfdata2=0\nlong_perfdata3=0\n",
      'state' => 0,
      'plugin_output' => 'plugin OK - output item 1',
      'perfdata' => 'perf_label1=0 perflabel2=0 long_perfdata1=0 long_perfdata2=0 long_perfdata3=0',
      'long_plugin_output' => "long output line 1\nlong output line 2\n"
    }
    );

plan tests => @specs * @fields + 1;

require_ok('NOMS::Nagios::Run');

for my $spec (@specs) {

    my $name = $spec->{'name'};
    my $output = $spec->{'complete_plugin_output'};

    my $runner = NOMS::Nagios::Run->new(
        {
            'command_line' => ( $spec->{'command'} || "printf '${output}'")
        });

    my $result = $runner->run();
    # diag(Data::Dumper->Dump([$result], ['result']));


    for my $field (@fields) {
        is($result->{$field}, $spec->{$field}, "${name}-${field}");
    }
}
