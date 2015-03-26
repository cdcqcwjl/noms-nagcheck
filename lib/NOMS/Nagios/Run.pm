#!perl
# /* Copyright 2013 Proofpoint, Inc. All rights reserved.
#    Copyright 2015 Evernote Corp. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# */


package NOMS::Nagios::Run;

use strict;
use vars qw($VERSION $context_fields);

use IPC::Run qw(start timeout);

sub new {
   my ($class, $context) = @_;
   # context holds things like configuration data, resources
   # from Nagios::Config

   my $self = bless({}, $class);

   $self->{'context'} = $context;
   
   $self->{'context'}->{'fields'} ||= [
      qw(host_name address service_description check_command command_line
   state plugin_output perfdata long_plugin_output check_time) ];

   return $self;
}

sub set {
   my ($self, @pairs) = @_;

   while (my ($key, $value) = splice(@pairs, 0, 2)) {
      $self->{'context'}->{$key} = $value;
   }
}

sub get {
   my ($self, $param) = @_;

   $self->{'context'}->{$param};
}

# Run the given command line, returning a data structure that is a partial
# response as documented in
# https://wiki.proofpoint.com/wiki/display/XOPS/Nagcheck+API
# long_plugin_output
# plugin_output (first line without perfdata)
# state (exitcode)
# perfdata
# context has: resources (global macros)
# selected Nagios::Config attributes (host_check_timeout,
# service_check_timeout)
# ARG macros from command definition (if applicable)
# HOSTNAME, HOSTALIAS and HOSTADDRESS, from Nagios or constructed
# SERVICEDESC (if applicable)
sub run {
   my ($self) = @_;
   my $context = $self->{'context'};
   my $result = { };

   $context->{'expanded_command_line'} =
       $self->expand_macros($context->{'command_line'});
   $context->{'check_timeout'} = 60
       unless exists($context->{'check_timeout'});

   my ($stdin, $stdout, $stderr);
   my $h;
   eval {
      my $h = start(['sh', '-c', $context->{'expanded_command_line'}],
                 \$stdin, \$stdout, \$stderr,
                 timeout($context->{'check_timeout'}));
      $h->finish();
      my $state = $h->result(0);
      if ($state < 0 or $state > 3) {
         $state = 3;
      }
      $result->{'state'} = $state;
   };
   if ($@) {
      if ($@ =~ /timeout/) {
         $stdout = "(timeout waiting $context->{'check_timeout'}) " .
             ($stdout ? ' ' : '') . $stdout;
         $result->{'state'} = 3; # UNKNOWN
      } else {
         die $@;
      }
   }

   $result->{'long_plugin_output'} = $stdout;
   if ($stderr) {
      my $c = '';
      if ($result->{'long_plugin_output'} and
          $result->{'long_plugin_output'} !~ /\n$/m) {
         $c = "\n";
      }
      $result->{'long_plugin_output'} .= $c . '(stderr) ' . $stderr;
   }

   my ($plugin_output) = split(/$/, $result->{'long_plugin_output'});
   $plugin_output = '' if !defined($plugin_output);
   my $perfdata;

   ($plugin_output, $perfdata) = split(/\s*\|\s*/, $plugin_output, 2);
   $result->{'plugin_output'} = $plugin_output;
   $result->{'perfdata'} = $perfdata;

   for my $param (qw(host_name address service_description
                     check_command command_line expanded_command_line)) {
      $result->{$param} = $context->{$param} if $context->{$param};
   }

   return $result;
}

sub expand_macros {
   my ($self, $s) = @_;

   $s =~ s/(\$[^\s\$]+\$)/$self->{'context'}->{$1}/ge;

   return $s;
}

1;
