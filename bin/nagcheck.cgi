#!/usr/bin/env perl
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


use strict;
no warnings; # Because CGI

use CGI;
use URI::Escape;
use PPOPS::JSON;
use Monitoring::Livestatus;
use NOMS::Nagios::Config;
use NOMS::Nagios::Run;
use Socket;
use POSIX;
use Sys::Syslog;
use Data::Dumper;

use vars qw($me $default_cfg_file $default $http_result
            $obj_desc $macro_desc @response_desc
            $livestatus $nag);

$default_cfg_file = '/usr/local/etc/nagcheck.conf';

$me = 'nagcheck';

$http_result = {
   200 => '200 OK',
   202 => '202 Accepted',
   400 => '400 Bad Request',
   403 => '403 Forbidden',
   404 => '404 Not Found',
   500 => '500 Internal Server Error'
};

$obj_desc = {
   'command' => {
      'key' => 'check_command',
      'keycol' => 'name',
      'columns' => [qw(name command_line)]
   },
          'host' => {
             'key' => 'host_name',
             'keycol' => 'host_name',
             'columns' => [qw(name alias address check_command)]
      },
                 'service' => {
                    'key' => 'service_description',
                    'keycol' => 'service_description',
                    'columns' => [qw(service_description check_command)]
             }
};

$macro_desc = {
   '$HOSTADDRESS$' => 'address',
   '$HOSTALIAS$' => 'alias',
   '$HOST$' => 'host_name',
   '$HOSTNAME$' => 'host_name',
   '$SERVICEDESC$' => 'service_description'
};

@response_desc = qw(host_name
   address
   service_description
   check_command
   command_line
   state
   plugin_output
   perfdata
   long_plugin_output
   check_time);

openlog($me, 'pid,ndelay,nofatal', 'daemon');
# Read Nagios Config

# Whole config is replaced in config file exists
my $cfg = {
   'nagios_cfg_file' => '/usr/local/nagios/etc/nagios.cfg',
   'allow_params' => [qw(timeout address report wait debug service_description command_line)],
   'livestatus' => { 'server' => 'localhost:10655' }
};

my $default = {
   'wait' => 1,
   'report' => 0
};

eval {
   if (open(my $cfg_file, '<',
            ($ENV{'NAGCHECK_CONFIG'} || $default_cfg_file))) {
      my $cfg_text = do { local $/; <$cfg_file> };
      close($cfg_file);
      my $cfg_hash = eat_json($cfg_text);
      $cfg = $cfg_hash if defined($cfg_hash) and ref($cfg_hash)
          and ref($cfg_hash) eq 'HASH';
   }
};
if ($@) {
   wrn("Problem reading $default_cfg_file, using default config: " . $@);
}

$nag = NOMS::Nagios::Config->new($cfg);
my $q = new CGI;

eval {
   $livestatus = Monitoring::Livestatus->new(%{$cfg->{'livestatus'}});
   
   my $path = $q->path_info;
   $path =~ s|^/||;
   my (@args) = map { s/\+/ /g; uri_unescape($_) } split('/', $path);
   dbg("extra path args = " . join(", ", @args));
   
   my ($op_name, $host_name, $arg) = @args;
   
   my $op = {
      'op' => $op_name,
      'host_name' => $host_name,
      'check_time' => time(),
      'check_timeout' =>
          (($op_name eq 'host' ? $nag->{'host_check_timeout'} :
           $nag->{'service_check_timeout'}) || 120)
   };
   
   if (defined($arg)) {
      $op->{'check_command'} = $arg if $op->{'op'} eq 'command';
      $op->{'service_description'} = $arg if $op->{'op'} eq 'service';
   }
   
   my @disallowed_params = ();
   for my $param ($q->param) {
      if (isin($param, @{$cfg->{'allow_params'}})) {
         dbg("setting query parameter $param to" . $q->param($param));
         $op->{$param} = $q->param($param);
      } else {
         push(@disallowed_params, $param);
      }
   }
   if (@disallowed_params) {
      result($q, 403, { "${me}_error" =>
                            "disallowed parameters not permitted: " .
                            join(', ', @disallowed_params) .
                            "; allowed parameters: " .
                            join(', ', @{$cfg->{'allow_params'}}) });
   }
   
   for my $param (keys %$default) {
      if (defined($op->{$param})) {
         $op->{$param} = bool_normalize($op->{$param});
      } else {
         $op->{$param} = $default->{$param};
      }
   }
   
   unless (isin($op->{'op'}, qw(host service command))) {
      result($q, 400, { "${me}_error" => "request type " . $op->{'op'} .
                            " not understood, must be host, " .
                            "service or command" });
   }
   
   if ($op->{'op'} ne 'host' and
       $op->{'report'} and
       (! defined($op->{'service_description'}) or
        ! $op->{'service_description'})) {
      result($q, 400, { "${me}_error" =>
                            "service argument or service_description " .
                            "must be given to report service status" });
   }
   
   if (! $op->{'report'} and ! $op->{'wait'}) {
      # Would be a no-op, possibly not a a bad request
      result($q, 400, { "${me}_error" =>
                            "meaningless to submit asynchronous nonreporting " .
                            "check" });
   }
   
   my $host = get_object('host', $op->{'host_name'});
   dbg("host = " . ddump($host));
   
   if (! $op->{'address'}) {
      # Let's see if nagios has it
      if ($host->{'address'}) {
         $op->{'address'} = $host->{'address'};
      } else {
         $op->{'address'} = lookup_host($op->{'host_name'});
      }
   }
   
   if (! $op->{'address'}) {
      result($q, 404, { "${me}_error" => "host $op->{'host_name'} not found " .
                            "in nagios or DNS" });
   }
   
   my $service = get_object('service', $op->{'service_description'})
       if ($op->{'service_description'});
   dbg("service = " . ddump($service)) if defined($service);
   
   if (! $op->{'check_command'}) {
      if ($op->{'op'} eq 'host') {
         dbg("setting op->check_command to $host->{'check_command'}");
         $op->{'check_command'} = $host->{'check_command'};
      } elsif ($op->{'op'} eq 'service') {
         $op->{'check_command'} = $service->{'check_command'};
      }
   }

   my $command = get_object('command', first_arg($op->{'check_command'}))
       if ($op->{'check_command'});
   dbg("command = " . ddump($command)) if defined($command);
   
   if (! $op->{'command_line'}) {
      # Find it from the check_command if given
      $op->{'command_line'} = $command->{'command_line'}
      if defined($command);
   }
   
   if (! $op->{'command_line'}) {
      result($q, 404, { "${me}_error" =>
                            "could not find command for $op->{'op'} check" .
                            " $op->{'service_description'}" });
   }
   
   if (! $op->{'wait'}) {
      # Need to close and reopen syslog?
      result($q, 202, $op);
      closelog();
      # Apparently close() is not sufficient
      open(STDIN, '<', '/dev/null');
      open(STDOUT, '>', '/dev/null');
      open(STDERR, '>', '/dev/null');
      fork && exit;
      setsid();
      openlog($me, 'pid,ndelay,nofatal', 'daemon');
   }
   
   my $macro = { %{$nag->{'resource'}} };
   for my $macname (keys %$macro_desc) {
      $macro->{$macname} = $op->{$macro_desc->{$macname}};
   }
   my $n = 0;
   for my $arg (split('!', $op->{'check_command'})) {
      $macro->{'$ARG' . $n . '$'} = $arg;
      $n++;
   }
   
   dbg("op    = " . ddump($op));
   dbg("macro = " . ddump($macro));
   
   my $run = NOMS::Nagios::Run->new({ %$op, %$macro });
   
   my $result = $run->run();
   
   for my $field (@response_desc) {
      if (! exists($result->{$field}) && defined($op->{$field})) {
         $result->{$field} = $op->{$field};
      }
   }

   delete($result->{'expanded_command_line'})
       unless $op->{'debug'};
   
   if ($op->{'report'}) {
      my ($succ, $mess) = report_status($op->{'op'}, $result);
      wrn("Could not report result to nagios: $mess: " . ddump($result)) unless $succ eq 'ok';
   }
   
   if ($op->{'wait'}) {
      # We're still in the web response
      result($q, 200, $result);
   }
};
if ($@) {
   if ($@ =~ /failed to connect/) {
      result($q, 500, { "${me}_error" => "could not connect to livestatus "
                            . "server $cfg->{'livestatus_server'}" });
   } else {
      result($q, 500, { "${me}_error" => "$@" });
   }
}

sub bool_normalize {
   my ($v) = @_;

   if (lc($v) eq 'true' or lc($v) eq 'yes' or lc($v) eq 'on') {
      return 1;
   } else {
      return 0;
   }
}

sub isin {
   my ($v, @a) = @_;

   no warnings;

   for my $c (@a) {
      return 1 if $v eq $c;
   }

   return 0;
}

sub result {
   my ($q, $code, $obj) = @_;
   my $h;

   $h = {
      -status => $http_result->{$code},
      -type => 'application/json'
   };
   $h->{'-content_length'} = 0 if !defined($obj);

   print $q->header($h), make_json($obj), "\n"; # TODO: \n or no?

   exit if $code > 399;
}

sub wrn {
   syslog('warning', join(' ', @_));
}

sub lookup_host {
   my ($hname) = @_;

   my $pip = gethostbyname($hname);
   return inet_ntoa($pip) if defined($pip);
}

sub get_object {
   my ($type, $keyval) = @_;

   my $query = join("\n",
                    "GET ${type}s",
                    "Columns: " . join(' ', @{$obj_desc->{$type}->{'columns'}}),
                    "Filter: " . $obj_desc->{$type}->{'keycol'} .
                    ' = ' . $keyval,
                    '');

   dbg("livestatus query: $query");

   my $r = $livestatus->selectall_arrayref($query,
                                           { Slice => { } },
                                           1);

   my $obj = $r->[0] if defined($r) && $r;

   return $obj;
}

sub first_arg {
   my ($s) = @_;

   my ($a) = split(/\!/, $s, 2);

   dbg("first_arg($s) -> $a");

   return $a;
}

sub dbg {
   my (@msg) = @_;

   print "DBG($me): ", join("\nDBG($me):    ", @msg), "\n"
       if $ENV{'TEST_DEBUG'};
}

sub ddump {
   my $v = 'v0';
   Data::Dumper->new([@_], [map { $v++ } @_])->Terse(1)->Indent(0)->Dump;
}

sub report_status {
   my ($op, $result) = @_;
   my $rv = ['error', undef];

   my $line;
   if ($op eq 'host') {
      $line = join(';',
                   'PROCESS_HOST_CHECK_RESULT',
                   $result->{'host_name'},
                   $result->{'state'},
                   condjoin(' | ', $result->{'plugin_output'},
                            $result->{'perfdata'}));
   } else {
      $line = join(';',
                   'PROCESS_SERVICE_CHECK_RESULT',
                   $result->{'host_name'},
                   $result->{'service_description'},
                   $result->{'state'},
                   condjoin(' | ', $result->{'plugin_output'},
                            $result->{'perfdata'}));
   }
   
   my $ts = $result->{'check_time'};

   dbg("result line = [$ts] $line");
   # Perl open not used here because there is no way to prevent
   # it using O_CREAT, AFAICT. We do not want to create the command
   # file if it already exists, which sometimes happens when nagios
   # restarts or fails to restarts or... well, sometimes it happens.
   # -jbrinkley/20110610
   if (sysopen(my $cmd_file, $nag->{'command_file'}, O_WRONLY)) {
      dbg("   writing to $nag->{'command_file'}");
      $rv->[1] = print $cmd_file "[$ts] ", $line, "\n";
      close($cmd_file);
      $rv->[0] = 'ok';
   } else {
      dbg("   couldn't write to $nag->{'command_file'} - $!");
      $rv->[1] = "couldn't write to $nag->{'command_file'} - $!";
   }

   return @$rv;
}

sub condjoin {
   my ($sep, $s, @s) = @_;

   return $s unless @s;

   my $h = shift(@s);

   return condjoin($sep, ($h ? join($sep, $s, $h) : $s), @s);
}
