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


package NOMS::Nagios::Config;

use vars qw($VERSION);
BEGIN { $VERSION = '__VERSION__'; }

use File::Spec;
use File::Basename;
use Data::Dumper;

sub new {
   my ($class, $opt) = @_;

   my $self = bless({}, $class);

   if (defined($opt)) {
      for my $key (keys %$opt) {
         $self->{'_config'}->{$key} = $opt->{$key};
      }
   }

   $self->{'_config'}->{'nagios_cfg_file'} ||=
       '/usr/local/nagios/etc/nagios.cfg';

   $self->read_cfg($self->{'_config'}->{'nagios_cfg_file'});

   if (defined($self->{'_config'}->{'set'})) {
      for my $key (keys %{$self->{'_config'}->{'set'}}) {
         $self->{$key} = delete($self->{'_config'}->{'set'});
      }
   }

   return $self;
}

sub cfg {
   my ($thing, $param, @rest) = @_;
   my $rv;

   return undef if $param eq '_config';

   return $thing unless ref($thing);
   return $thing unless defined($param);

   if (ref($thing) eq 'ARRAY') {
      $rv = $thing->[$param];
   } else {
      $rv = $thing->{$param};
   }

   return @rest ? cfg($rv, @rest) : $rv;
}


sub read_cfg {
   my ($self, $file, $namespace) = @_;
   my $paramct = 0;

   my $target = $self;
   if (defined($namespace)) {
      $self->{$namespace} ||= { };
      $target = $self->{$namespace};
   }

   if (open(my $fh, '<', $file)) {
      $self->dbg("reading $file");
      while (defined(my $line = <$fh>)) {
         next if $line =~ /^\s*$/;
         next if $line =~ /^\s*\#/;
         chomp($line);
         $line =~ s/\s*\#.*//;
         my ($param, $value) = split(/\s*=\s*/, $line);
         $paramct++;
         { no warnings;
           $self->dbg("setting $param = $value (namespace $namespace)"); }
         if (is_in($param, 'cfg_dir', 'cfg_file')) {
            $target->{$param} ||= [ ];
            push(@{$target->{$param}}, $value);
         } else {
            $target->{$param} = $value;
         }
      }
      close($fh);
   }

   if ($target->{'resource_file'}) {
      my $rfile = $target->{'resource_file'};
      if (! File::Spec->file_name_is_absolute($rfile)) {
         $rfile = File::Spec->join(dirname($file), $rfile);
      }
      $self->dbg("calling read_cfg($rfile, 'resource')");
      $self->read_cfg($rfile, 'resource');
   }

   return $paramct;
}

sub dump {
   my ($self) = @_;
   my @lines;

   for my $param (keys %$self) {
      next if $param eq '_config';
      if (ref($self->{$param}) and ref($self->{$param}) eq 'ARRAY') {
         for my $value (@{$self->{$param}}) {
            push(@lines, $param . '=' . $value);
         }
      } else {
         push(@lines, $param . '=' . $self->{$param});
      }
   }

   return @lines;
}

sub dbg {
   my ($self, @msg) = @_;
   my $class = ref($self);

   print "DBG($class): ", join("\nDBG($class):    ", @msg), "\n"
       if $self->{'_config'}->{'debug'};
}

sub is_in {
   my ($cand, @arr) = @_;

   for my $el (@arr) {
      return 1 if $el eq $cand;
   }

   return 0;
}

sub ddump {
   my $v = 'v0';
   Data::Dumper->new([@_],[map { $v++ } @_])->Terse(1)->Indent(0)->Dump;
}

1;
