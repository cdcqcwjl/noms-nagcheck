#!perl

use lib 'lib';
use Module::Build;

my $build = Module::Build->new
    (
     module_name => 'NOMS::Nagcheck',
     license  =>    'Apache_2_0',
     dist_author => 'Jeremy Brinkley <jbrinkley@evernote.com>',
     dist_abstract => 'Run Nagios plugins from the web',
     dist_version => sub {
         require 'NOMS/Nagcheck/Version.pm';
         $NOMS::Nagcheck::Version::VERSION;
     }->(),
     script_files => {
         'bin/nagcheck'           => 'bin/nagcheck'
     },
     pm_files => {
         'lib/NOMS/Nagios/Config.pm'  => 'lib/NOMS/Nagios/Config.pm',
         'lib/NOMS/Nagios/Run.pm'     => 'lib/NOMS/Nagios/Run.pm'
     },
     requires => {
         'perl'          => '5.6.1',
         'URI::Escape'   => 0,
         'JSON'          => 0,
         'Monitoring::Livestatus' => 0,
         'IPC::Run'      => 0
     },
     meta_merge => {
         resources => {
             repository => 'http://github.com/evernote/noms-nagcheck'
         }
     },
     test_requires => {
         'Test::Spec'      => 0,
         'JSON'            => '>= 2.0',
         'Class::Accessor' => 0
     }
    );

$build->create_build_script;
