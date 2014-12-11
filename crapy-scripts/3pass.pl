#!/usr/bin/perl

# add 3 class, one for each pass
# replace reports with a call to method rudder_common_report on pass 3
#
use strict;
use warnings;

my $file = $ARGV[0];

my @order = qw/meta vars defaults classes files packages guest_environments methods processes services commands storage databases reports/;
my $i=1;
my %order = map { $_ => $i++ } @order;

open(my $fh, "<$file") or die "can't open $file";

my %bundles;
my %bundle_reports;

# read the file to index reports
my $bundle="";
my $ptypes={};
my $reporting=0;
while(my $line=<$fh>) {
  if($line =~ /^\s*bundle\s+\w+\s+(\w+)/) {
    store_bundle();
    $bundle=$1;
    $ptypes={};
    $bundle_reports{$bundle}="";
  } elsif($line =~ /^\s*(\w+):\s*$/) {
    $ptypes->{$1} = 1;
    if($1 eq "reports") { $reporting=1; }
    else { $reporting=0; }
  } elsif($line =~ /^\s*}\s*(#.*)?$/) { # end of bundle
    $reporting=0;
  }

  if($reporting) {
    $bundle_reports{$bundle} .= $line;
  }

}
store_bundle();

close($fh);

open($fh, "<$file") or die "can't open $file";
open(my $fh2, ">$file.2") or die "can't open $file.2";

# read the file and write output file
$bundle="";
my $pass_needed=0;
my $report_needed=0;
my $ptype="";
while(my $line=<$fh>) {
  if($line =~ /^\s*bundle\s+agent\s+(\w+)/) {
    $bundle=$1;
    $ptype="";
    if(defined $bundles{$bundle}) {
      if(defined $bundles{$bundle}->{'reports'}) {
        $pass_needed=1;
        $report_needed=1;
      } else {
        $pass_needed=0;
        $report_needed=0;
      }
    } else {
      $pass_needed=0;
      $report_needed=0;
    }
  } elsif($line =~ /^\s*bundle\s+/) {
    $bundle=""
  } elsif($bundle ne "" && $line =~ /^\s*(\w+):\s*$/) { # in a good bundle, 3pass not yet written, before new promise type
    my $this_type=$1;
    if($pass_needed) {
      ptype_change($ptype, $this_type);
    }
    if($report_needed) {
      ptype_change2($ptype, $this_type);
    }
    $ptype=$this_type;
  } elsif($line =~ /^\s*}\s*(#.*)?$/) { # end of bundle
    if($pass_needed) {
      ptype_change($ptype, "");
    }
    $ptype="";
  } 
  if($ptype eq "reports") {
    $line="";
  }
  print $fh2 $line;
}

close($fh2);
close($fh);

sub store_bundle
{
  return if $bundle eq "";
  $bundles{$bundle} = $ptypes;
}


sub ptype_change
{
  my ($last, $next) = @_;

  # 3pass writing
  if(defined $bundles{$bundle}->{'classes'}) { # has classe -> wait for the end of classes:
    if($last eq "classes") {
      write_3pass($fh2);
    }
  } elsif(is_after($next, 'classes') ) { # has no classes -> wait for the next ptype
    print $fh2 "  classes:\n";
    write_3pass($fh2);
  }
}

sub ptype_change2
{
  my ($last, $next) = @_;

  # reporting writing
  if(defined $bundles{$bundle}->{'methods'}) { # has methods -> wait for end of methods
    if($last eq "methods") {
      write_reports($fh2);
    }
  } elsif(is_after($next, 'methods') ) { # has no methods -> wait for the next ptype
    print $fh2 "  methods:\n";
    write_reports($fh2);
  }
}

sub write_3pass
{
  my $fh = shift;
  print $fh '    any::
      "pass3" expression => "pass2";
      "pass2" expression => "pass1";
      "pass1" expression => "any";

';
  $pass_needed=0;
}

sub write_reports
{
  my $fh = shift;
  my $any = 1;
  for my $line (split /\n/, $bundle_reports{$bundle}) {
    next if($line =~ /^\s*reports:/);

    if($any) {
      if($line =~ /^\s*.*::\s*$/) {
        $any = 0;
      } elsif($line =~ /^\s*#.*/) {
      } elsif($line =~ /^\s*$/) {
      } else {
        print $fh "    pass3::\n";
        $any=0;
      }
    }

    if($line =~ /^\s*(\w+)::\s*$/) { # simple class expression
      print $fh "    pass3.$1::\n";
    } elsif($line =~ /^\s*(.*)::\s*$/) { # generic class expression
      print $fh "    pass3.($1)::\n";
    } elsif($line =~ /^\s*#.*$|^\s*$/) { # comment
      print $fh "$line\n";

      # "@@sudoParameters@@result_success@@${sudo_directive_id[${sudo_index}]}@@sudoersFile@@None@@${g.execRun}##${g.uuid}@#The sudoers file did not require any modification"
      # @@Policy@@Type@@RuleId@@DirectiveId@@VersionId@@Component@@Key@@ExecutionTimeStamp##NodeId@#HumanReadableMessage
      # "@@${technique_name}@@${status}@@${identifier}@@${component_name}@@${component_key}@@${g.execRun}##${g.uuid}@#${message}";
      # bundle agent rudder_common_report(technique_name, status, identifier, component_name, component_key, message)
    } elsif($line =~ /^\s*"@@(.*?)@@(.*?)@@(.*?)@@(.*?)@@(.*?)@@(.*?##.*?)@#(.*?)"\s*([;,]?)\s*$/) { # report
      my ($Policy, $Type, $DirectiveVersionId, $Component, $Key, $TSnID, $HumanReadableMessage, $punc) = ($1,$2,$3,$4,$5,$6,$7,$8);
      print $fh "      \"any\" usebundle => rudder_common_report(\"$Policy\", \"$Type\", \"$DirectiveVersionId\", \"$Component\", \"$Key\", \"$HumanReadableMessage\")$punc\n";
    } elsif($line =~ /^\s*ifvarclass/) { # promise attribute
      print $fh "$line\n";
    } elsif($line =~ /^\s*&.*&\s*$/) { # string template
      print $fh "$line\n";
    } else { # inknown line
      print "XXX can't parse $line in $file\n";
    }
  }
  print $fh "\n";
  $report_needed=0;
}

sub is_after
{
  my($ptype, $point) = @_;
  return 1 if($ptype eq "");
  return $order{$ptype} > $order{$point};
}
