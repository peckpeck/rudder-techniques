#!/usr/bin/perl

# detect how many passes are needed for each bundle
#
use warnings;
use strict;

my $debug=0;
my %classes_pass;
my $block_pass=1;
my $promise_pass=1;
my $maxpass=1;
my $memclass="";
my $fh;
my $file=$ARGV[0];
my $because="";
print ": $file\n";
my $class_mode=0;
my $pass=0;
my $lineno=0;

for($pass=1;$pass<=4;$pass++) {
  open($fh, "<$file");
  $lineno=0;;
  while(my $line=<$fh>) {
    $lineno++;
    if($line =~ /^\s*classes:\s*$/) {
      $class_mode=1;
      $block_pass=1;
      $promise_pass=1;
    } elsif($line =~ /^\s*\w+:\s*$/) {
      $class_mode=0;
      $block_pass=1;
      $promise_pass=1;
    } elsif($class_mode) {
      if($line =~ /^\s*"(.*?)"/) {
        $memclass = "$memclass,$1";
      } elsif($line =~ /^\s&.*"(.*?)"/) {
        $memclass = "$memclass,$1";
      }
      if($line =~ /expression\s*=>\s*"(.*?)"/) {
        my $classexpr = $1;
        for my $class (split /\s*[(),.&|!]\s*/, $classexpr) {
          $class =~ s/\s*(?:\w+\s*\()?(.*?)\s*/$1/;
          $class =~ s/\$[{(]([\w\[\]]+)[)}]//g;
          $class =~ s/\$[{(]([\w\[\]]+)[)}]//g;
          $class =~ s/\$[{(]([\w\[\]]+)[)}]//g;
          next if $class =~ /^\s*$/;
          $promise_pass = classuse($class, $promise_pass, $pass);
          print "$lineno: classuse_dynamic $pass: $class -> $promise_pass\n" if $debug;
          if($promise_pass > $maxpass) {
            $maxpass = $promise_pass;
            $because = "because $class is used in pass $promise_pass in ifvarclass, line $lineno";
          }
        }
      }
    } elsif($line =~ /^\s*(.*)::\s*$/) {
      my $classexpr = $1;
      $block_pass=1;
      my $b = "";
      for my $class (split /\s*[(),.&|!]\s*/, $classexpr) {
        $block_pass = classuse($class, $block_pass, $pass);
        $b = "$class is used in pass $block_pass statically";
        print "$lineno: classuse_static $pass: $class -> $block_pass\n" if $debug;
      }
      $promise_pass=$block_pass;
      if($promise_pass > $maxpass) {
        $maxpass = $promise_pass;
        $because = "because $b, line $lineno";
      }
    }
  
    if($line =~ /restart_class\s*=>\s*"(.*)"/) {
      $memclass = "$memclass,$1";
    }
    if($line =~ /ifvarclass\s*=>\s*"(.*)"/) {
      my $classexpr = $1;
      for my $class (split /\s*[(),.&|!]\s*/, $classexpr) {
        $class =~ s/\s*(?:\w+\s*\()?(.*?)\s*/$1/;
        $class =~ s/\$[{(]([\w\[\]]+)[)}]//g;
        $class =~ s/\$[{(]([\w\[\]]+)[)}]//g;
        $class =~ s/\$[{(]([\w\[\]]+)[)}]//g;
        next if $class =~ /^\s*$/;
        $promise_pass = classuse($class, $promise_pass, $pass);
        print "$lineno: classuse_dynamic $pass: $class -> $promise_pass\n" if $debug;
        if($promise_pass > $maxpass) {
          $maxpass = $promise_pass;
          $because = "because $class is used in pass $promise_pass in ifvarclass, line $lineno";
        }
      }
    }
    if($line =~ /classes\s*=>.*?\((.*)\)\s*[,;]/) {
      $memclass = "$memclass,$1";
    }
  
    if($line =~ /;\s*$/) {
      if($memclass ne "") {
        my $classexpr = $memclass;
        for my $class (split /\s*,\s*/, $classexpr) {
          $class =~ s/\s*"(.*)"\s*/$1/;
          classdef($class);
        }
        $memclass="";
      }
      $promise_pass=$block_pass;
    }
  }
  close($fh);
  for my $k (keys %classes_pass) {
    $classes_pass{$k}++;
  }
  print "Max pass = $maxpass $because \n"; 
}
print STDERR "$file $maxpass\n";

sub classuse
{
  my ($class, $promise_pass, $pass) = @_;
  my $return_pass = 1;
  return 1 if($class =~ /^\s*$/);
  for my $defclass (keys %classes_pass) {
#    print "$lineno: compare $defclass / $class\n" if $debug;
    my $regex1 = "^$class\$";
    if($defclass =~ /_$/) { $regex1 = "^$class"; }
    if($defclass =~ /^_/) { $regex1 = "$class\$"; }
    my $regex2 = "^$defclass\$";
    if($class =~ /_$/) { $regex2 = "^$defclass"; }
    if($class =~ /^_/) { $regex2 = "$defclass\$"; }
    if($defclass =~ /$regex1/ || $class =~ /$regex2/) {
#      if($classes_pass{$defclass}+1 <= $pass) { 
#        $return_pass = max($classes_pass{$defclass}+1, $return_pass);
#      }
#      if($classes_pass{$defclass} == $pass) { 
#        $return_pass = max($pass, $return_pass);
#      }
#
      $return_pass = max($classes_pass{$defclass}, $return_pass);
#      print "$lineno: class_defined $class/$defclass: -> $return_pass\n" if $debug;
    }
  }
  return $return_pass;
}

sub classdef
{
  my $class = shift;
  $class =~ s/\$[{(]([\w\[\]])[)}]//g;
  $class =~ s/\$[{(]([\w\[\]])[)}]//g;
  $class =~ s/\$[{(]([\w\[\]])[)}]//g;
  $class =~ s/&.*?&//g;
  return if($class =~ /^\s*$/);
  if(defined $classes_pass{$class}) { $classes_pass{$class}--; $classes_pass{$class} = $promise_pass; }
  else { $classes_pass{$class} = $promise_pass; }
  print "$lineno: classdef $pass: $class -> $classes_pass{$class}\n" if $debug;
}

sub max
{
  my ($a, $b) = @_;
  return $a if $a > $b;
  return $b;
}
