#!/usr/bin/perl

use warnings;
use strict;

binmode(STDOUT, ":utf8");

### DO NOT INCLUDE
use FixAssessmentsManagerLib;

### DO INCLUDE
##################################################################################### 
# This program applies the following fixes to annotations of graph assessment items:
#
# (1a) Load global equals
# (1b) Go through annotation tab files and collect KBID from linking tab files for
# each entity span via entity mention span. 
#    - then collapse it with assessment package by adding pipe to object ECs
# (2) For each kit in assessment package merge ECs into expanded set
# (3) Read the output assessment package to obtain output filename and linenums for 
#     each assessment entry and update object ECs to the expanded set
# (4) Correct relations

# Author: Shahzad Rajput
# Please send questions or comments to shahzadrajput "at" gmail "dot" com
#
# For usage, run with no arguments
##################################################################################### 

my $version = "2019.0.0";

# Filehandles for program and error output
my $program_output = *STDOUT{IO};
my $error_output = *STDERR{IO};

##################################################################################### 
# Subroutines
##################################################################################### 
my $relation_ecs;
my $next_ec_num = 1000;

sub next_ec {
  my $next_ec = "NILR$next_ec_num";
  $next_ec_num++;
  $next_ec;
}

sub undo_normalize {
  my ($entry) = @_;
  my %undo_normalize = (CORRECT => "correct", INCORRECT => "wrong", YES => "yes", NO => "no");
  foreach my $key(qw(ASSESSMENT OBJECT_LINKABILITY PREDICATE_JUSTIFICATION_CORRECTNESS)) {
    my $value = $entry->get($key);
    if(defined $value && exists $undo_normalize{$value}) {
      $entry->set($key, $undo_normalize{$value});
    }
  }
}

sub relation_entry_to_ec {
  my ($entry, $arg1_assessment_entry, $arg2_assessment_entry) = @_;
  my $relation_type = $entry->get("RELATION_TYPE");
  my $arg1_label = $entry->get("ARG1_LABEL");
  my $arg2_label = $entry->get("ARG2_LABEL");
  my $arg1_ec = $arg1_assessment_entry->get("OBJECT_FQEC");
  my $arg2_ec = $arg2_assessment_entry->get("OBJECT_FQEC");
  my $key;
  if($arg1_label eq $arg2_label) {
    $key = $arg1_ec . "=" . $arg1_label . "_" . $relation_type . "_" . $arg2_label . "=" . $arg2_ec;
  }
  else {
    my $arg_ecs = {$arg1_label=>$arg1_ec, $arg2_label => $arg2_ec};
    my @labels = sort keys %{$arg_ecs};
    my @ecs = map {$arg_ecs->{$_}} @labels;
    $key = $ecs[0] . "=" . $labels[0] . "_" . $relation_type . "_" . $labels[1] . "=" . $ecs[1];
  }
  my $ec;
  if($relation_ecs->{$key}) {
    $ec = $relation_ecs->{$key};
  }
  else {
    $ec = next_ec();
    $relation_ecs->{$key} = $ec;
  }
  $ec;
}

sub get_global_equals_string {
  my ($global_equals, $input_ec_set) = @_;
  my %ecs;
  foreach my $ec(split(/\|/, $input_ec_set)) {
    $ecs{$ec} = 1;
    if($global_equals->{$ec}) {
      foreach my $set(keys %{$global_equals->{$ec}}) {
        foreach my $member(split(/\|/, $set)) {
          $ecs{$member} = 1;
        }
      }
    }
  }
  join("|", sort keys %ecs);
}

sub get_ecs_from_object_jusification {
  my ($mentions, $object_justification) = @_;
  my %ecs;
  foreach my $mention_id(keys %{$mentions->{SPAN_TO_MENTIONIDS}{$object_justification}}) {
    foreach my $kb_id(keys %{$mentions->{MENTIONID_TO_KBIDS}{$mention_id}}) {
      $ecs{$kb_id} = 1;
    }
  }
  join("|", sort keys %ecs);
}

sub entry_to_key {
  my ($entry, $fields) = @_;
  join("::", map {$entry->get($_)} @$fields);
}

##################################################################################### 
# Runtime switches and main program
##################################################################################### 

# Handle run-time switches
my $switches = SwitchProcessor->new($0, "Fix assessments",
                        "");
$switches->addHelpSwitch("help", "Show help");
$switches->addHelpSwitch("h", undef);
$switches->addVarSwitch('error_file', "Specify a file to which error output should be redirected");
$switches->put('error_file', "STDERR");
$switches->addConstantSwitch('allow_existing_outputdir', 'true', "Output directory may exist and will not be overwritten");
$switches->addImmediateSwitch('version', sub { print "$0 version $version\n"; exit 0; }, "Print version number and exit");
$switches->addParam("ambiguous", "required", "tab version of duplicate_aug_entries_mapping.xlsx");
$switches->addParam("annotations", "required", "Directory containing annotation tab files");
$switches->addParam("input", "required", "Assessment package as receieved from LDC");
$switches->addParam("output", "required", "Output directory");

$switches->process(@ARGV);

my $logger = Logger->new();
my $error_filename = $switches->get("error_file");
$logger->set_error_output($error_filename);
$error_output = $logger->get_error_output();

foreach my $path(($switches->get("ambiguous"),
                  $switches->get("annotations"),
                  $switches->get("input"))) {
  $logger->NIST_die("$path does not exist") unless -e $path;
}

my $global_equals_filename = $switches->get("ambiguous");
my $allow_existing_outputdir = $switches->get("allow_existing_outputdir");
my $input_assessments_dir = $switches->get("input");
my $output_assessments_dir = $switches->get("output");
$logger->NIST_die("$output_assessments_dir already exists") if(!$allow_existing_outputdir && -e $output_assessments_dir);

# copy input assessment package to output
system("cp -r $input_assessments_dir $output_assessments_dir") unless -e $output_assessments_dir;

# (1a) Load global equals
my $global_equals;
open(FILE, $global_equals_filename);
while(my $line = <FILE>) {
  chomp $line;
  my @ecs = sort keys {map {$_=>1} split(/\|/, $line)};
  foreach my $ec(@ecs) {
    $global_equals->{$ec}{$line} = 1;
  }
}
close(FILE);

# No more desired due to unexpected merged ECs as a result of errors in annotations/assessments.
#
# For example the case where the object with span "IC001L3FF:IC001L4NY:(1191,0)-(1195,0)”
# from annotation is in equivalence class 703448|80000027 but the assessment package
# includes this in 80000373.
#
# AIDA_TA2_GR_2019_0011           Life.Die.DeathCausedByViolentEvents_Place                LDC2019E43:703448|LDC2019E43:80000027      GPE        Kiev,Kyiv (a.k.a. Kiev)
# AIDA_TA2_GR_2019_0041           Life.Die.DeathCausedByViolentEvents_Place        LDC2019E43:80000373  FAC        Oles Buzyna's home
#
#--ASSSESSMENT_LINE = Life.Die.DeathCausedByViolentEvents_Place  202     Life.Die.DeathCausedByViolentEvents_Place       IC001L3FF       NIL     NIL
#     NIL     IC001L4NY:(1191,0)-(1195,0)     IC001L4NY:(1140,0)-(1151,0);IC001L4NY:(1191,0)-(1195,0) correct yes     80000373        NILV80000261
#--ECS_FROM_ANNOTAION = 703448|80000027
#--FILENAME = input/LDC2019R30_AIDA_Phase_1_Assessment_Results_V6.0/data/graph/batch2/BATCH2_Life.Die.DeathCausedByViolentEvents_Place_1_1.tab
#--LINENUM = 147
#--MENTION_INFO_FROM_ANNOTATION =
#     MENTION_ID=EMIC001L3FF.000063 KB_ID=703448|80000027
#     MENTION_ID=EMIC001L3FF.000162 KB_ID=703448|80000027
#     MENTION_ID=EMIC001L3FF.000321 KB_ID=703448|80000027
#     MENTION_ID=EMIC001L3FF.000420 KB_ID=703448|80000027
#     MENTION_ID=EMIC001L3FF.000493 KB_ID=703448|80000027
#--MERGED_ECS_STRING = 703448|80000027|80000373
#--OBJECT_FQEC_FROM_ASSESSMENT = 80000373
#--OBJECT_JUSTIFICATION = IC001L3FF:IC001L4NY:(1191,0)-(1195,0)


## (1b) Go through annotation tab files and collect KBID from linking tab files for
## each entity span via entity mention span.
##    - then collapse it with assessment package by adding pipe to object ECs
#
#my $mentions;
#my $annotations_dir = $switches->get("annotations");
#foreach my $topic(<$annotations_dir/data/*>) {
#  my (undef, $topic_id) = $topic =~ /(.*?\/)+(.*?)$/;
#  my $arg_mentions_filename = "$annotations_dir/data/$topic_id/$topic_id\_arg_mentions.tab";
#  foreach my $entry(FileHandler->new($logger, $arg_mentions_filename)->get("ENTRIES")->toarray()) {
#    my $mention_id = $entry->get("argmention_id");
#    my $document_id = $entry->get("root_uid");
#    my $document_element_id = $entry->get("child_uid");
#    my $textoffset_startchar = $entry->get("textoffset_startchar");
#    my $textoffset_endchar = $entry->get("textoffset_endchar");
#    my $keyframe_id = $entry->get("keyframe_id");
#    my $mediamention_coordinates = $entry->get("mediamention_coordinates");
#    next if $document_element_id eq "EMPTY_TBD";
#    my $span;
#    if($textoffset_startchar && $textoffset_endchar && $textoffset_startchar =~ /^\d+$/ && $textoffset_endchar =~ /^\d+$/ ) {
#      $span = $document_id .
#              ":" .
#              $document_element_id .
#              ":" .
#              "(" . $textoffset_startchar . "," . "0" . ")" .
#              "-" .
#              "(" . $textoffset_endchar . "," . "0" . ")";
#      $mentions->{MENTIONID_TO_SPANS}{$mention_id}{$span} = 1;
#      $mentions->{SPAN_TO_MENTIONIDS}{$span}{$mention_id} = 1;
#    }
#    else {
#      $document_element_id = $keyframe_id if $keyframe_id ne "EMPTY_NA";
#      if($mediamention_coordinates =~ /^\d+,\d+,\d+,\d+$/) {
#        my ($sx, $sy, $ex, $ey) = split(",", $mediamention_coordinates);
#        $span = $document_id .
#              ":" .
#              $document_element_id .
#              ":" .
#              "(" . $sx . "," . $sy . ")" .
#              "-" .
#              "(" . $ex . "," . $ey . ")";
#        $mentions->{MENTIONID_TO_SPANS}{$mention_id}{$span} = 1;
#        $mentions->{SPAN_TO_MENTIONIDS}{$span}{$mention_id} = 1;
#      }
#    }
#  }
#  my $kb_linking_filename = "$annotations_dir/data/$topic_id/$topic_id\_kb_linking.tab";
#  foreach my $entry(FileHandler->new($logger, $kb_linking_filename)->get("ENTRIES")->toarray()) {
#    my $kb_id = $entry->get("kb_id");
#    my $mention_id = $entry->get("mention_id");
#    $mentions->{MENTIONID_TO_KBIDS}{$mention_id}{$kb_id} = 1;
##    The following is not desired, because in the context of the mention KB-IDs
##    are confusable but its not true globally
##
##    # if kb_id is a list, add update global equals
##    if($kb_id =~ /\|/) {
##      my @ecs = sort keys {map {$_=>1} split(/\|/, $kb_id)};
##      foreach my $ec(@ecs) {
##        $global_equals->{$ec}{$kb_id} = 1;
##      }
##    }
#  }
#}

# (2) For each kit in assessment package merge ECs
my $input_assessments = Assessments->new($logger, $input_assessments_dir, "graph");
my %equals;
foreach my $entry($input_assessments->toarray()) {
  next unless ($entry->get("PREDICATE_JUSTIFICATION_CORRECTNESS") eq "CORRECT" && $entry->get("OBJECT_LINKABILITY") eq "YES");
  my ($filename, $linenum) = map {$entry->get("WHERE")->{$_}} qw(FILENAME LINENUM);
  my $predicate = $entry->get("PREDICATE");
  my $document_id = $entry->get("DOCUMENT_ID");
  my $object_justification = $entry->get("OBJECT_JUSTIFICATION");
  $object_justification = $document_id . ":" . $object_justification;
  # my $ecs_from_annotation = get_ecs_from_object_jusification($mentions, $object_justification);
  my $ecs_string = $entry->get("OBJECT_FQEC");
  # $ecs_string = $ecs_string . "|" . $ecs_from_annotation if $ecs_from_annotation;
  $ecs_string = get_global_equals_string($global_equals, $ecs_string);
  my @ecs = sort keys {map {$_=>1} split(/\|/, $ecs_string)};
  # If there is a generated ID as well as a manually assigned ID then prefer the manual one
  @ecs = grep {$_ !~ /^NILG\d+$/} @ecs
    if(scalar (grep {$_ =~ /^NILG\d+$/} @ecs) && scalar (grep {$_ !~ /^NILG\d+$/} @ecs));
  foreach my $ec1(@ecs) {
    foreach my $ec2(@ecs) {
      $equals{$predicate}{$ec1}{$ec2} = 1 if($ec1 ne $ec2);
    }
  }
}

restart:
foreach my $predicate(keys %equals) {
  foreach my $k1(keys %{$equals{$predicate}}) {
    foreach my $k2(keys %{$equals{$predicate}{$k1}}) {
      foreach my $k3(keys %{$equals{$predicate}{$k1}}) {
        next if $k2 eq $k3;
        unless(exists $equals{$predicate}{$k2}{$k3}) {
          $equals{$predicate}{$k2}{$k3} = 1;
          goto restart;
        }
      }
    }
  }
}

my $next_id = 1;
my %ids;
foreach my $predicate(sort keys %equals) {
  foreach my $ec1(sort keys %{$equals{$predicate}}) {
    my $id;
    if(exists $ids{$predicate}{EC_TO_ID}{$ec1}) {
      $id = $ids{$predicate}{EC_TO_ID}{$ec1};
    }
    foreach my $ec2(sort keys %{$equals{$predicate}{$ec1}}) {
      $logger->NIST_die("Multiple IDs")
        if ($id &&
            exists $ids{$predicate}{EC_TO_ID}{$ec2} &&
            $id != $ids{$predicate}{EC_TO_ID}{$ec2});
      $id = $ids{$predicate}{EC_TO_ID}{$ec2}
        if(exists $ids{$predicate}{EC_TO_ID}{$ec2} && !$id);
      if($id && not exists $ids{$predicate}{EC_TO_ID}{$ec1}) {
        $ids{$predicate}{EC_TO_ID}{$ec1} = $id;
      }
      if($id && not exists $ids{$predicate}{EC_TO_ID}{$ec2}) {
        $ids{$predicate}{EC_TO_ID}{$ec2} = $id;
      }
    }
    unless($id) {
      $id = $next_id;
      $ids{$predicate}{EC_TO_ID}{$ec1} = $id;
      $next_id++;
      foreach my $ec2(sort keys %{$equals{$predicate}{$ec1}}) {
        unless(exists $ids{$predicate}{EC_TO_ID}{$ec2}) {
          $ids{$predicate}{EC_TO_ID}{$ec2} = $id;
        }
      }
    }
  }
  
  foreach my $ec(keys %{$ids{$predicate}{EC_TO_ID}}) {
    my $id = $ids{$predicate}{EC_TO_ID}{$ec};
    $ids{$predicate}{ID_TO_ECS}{$id}{$ec} = 1;
  }
}

# (3) Read the output assessment package to obtain output filename and linenums for 
#     each assessment entry and update object ECs to the expanded set
my $store;
my $key_fields = [qw(PREDICATE DOCUMENT_ID PREDICATE_JUSTIFICATION OBJECT_JUSTIFICATION)];
my $arg_key_fields = {ARG1 => [qw(ARG1_PREDICATE ARG1_DOCID ARG1_PREDICATE_JUSTIFICATION ARG1_OBJECT_JUSTIFICATION)],
                      ARG2 => [qw(ARG2_PREDICATE ARG2_DOCID ARG2_PREDICATE_JUSTIFICATION ARG2_OBJECT_JUSTIFICATION)]};
my $output_assessments = Assessments->new($logger, $output_assessments_dir, "graph");
foreach my $entry($output_assessments->toarray()) {
  my ($filename, $linenum) = map {$entry->get("WHERE")->{$_}} qw(FILENAME LINENUM);
  my $predicate = $entry->get("PREDICATE");
  my $id;
  foreach my $ec(sort split(/\|/, $entry->get("OBJECT_FQEC"))) {
    $id = $ids{$predicate}{EC_TO_ID}{$ec} unless $id;
    # sanity check
    $logger->NIST_die("Unexpected multiple IDs; expecting exactly one")
      if($id && exists $ids{$predicate}{EC_TO_ID}{$ec} && $id != $ids{$predicate}{EC_TO_ID}{$ec});
  }
  if($id) {
    # apply correction only if $id is defined
    my $new_fqec = join("|", sort keys %{$ids{$predicate}{ID_TO_ECS}{$id}});
    $entry->set("OBJECT_FQEC", $new_fqec);
  }
  # Recover blank KBID for relations
  if($entry->get("SUBJECT_FQEC") =~ /^NILG\d+$/ && $entry->get("SUBJECT_FQEC_READ") eq "") {
    $entry->set("SUBJECT_FQEC", $entry->get("SUBJECT_FQEC_READ"));
  }
  # Undo normalization of correctness and linkability
  undo_normalize($entry);
  my $key = entry_to_key($entry, $key_fields);
  $store->{ENTRY_BY_FILEANDLINE}{$filename}{$linenum} = $entry;
  die "Multiple entries for key=$key" if $store->{ENTRY_BY_KEY}{$key};
  $store->{ENTRY_BY_KEY}{$key} = $entry;
}

# (4) Correct relations
my $relation_pool_filename = "$output_assessments_dir/data/graph/relation-pool-v2.0.tab";
my $header = Header->new($logger, 
                            join ("\t", qw(RELATION_TYPE 
                                            ARG1_LABEL
                                            ARG1_DOCID 
                                            ARG1_PREDICATE_JUSTIFICATION 
                                            ARG1_OBJECT_JUSTIFICATION
                                            ARG1_EC
                                            ARG2_LABEL
                                            ARG2_DOCID
                                            ARG2_PREDICATE_JUSTIFICATION
                                            ARG2_OBJECT_JUSTIFICATION
                                            ARG2_EC
                                            ASSESSMENT)));
foreach my $entry(FileHandler->new($logger, $relation_pool_filename, $header)->get("ENTRIES")->toarray()) {
  $entry->{MAP}{ARG1_PREDICATE} = $entry->get("RELATION_TYPE") . "_" . $entry->get("ARG1_LABEL");
  $entry->{MAP}{ARG2_PREDICATE} = $entry->get("RELATION_TYPE") . "_" . $entry->get("ARG2_LABEL");
  my $assessment = $entry->get("ASSESSMENT");
  next if($assessment eq "no");
  my $arg1_key = entry_to_key($entry, $arg_key_fields->{"ARG1"});
  my $arg2_key = entry_to_key($entry, $arg_key_fields->{"ARG2"});
  my $arg1_assessment_entry = $store->{ENTRY_BY_KEY}{$arg1_key};
  my $arg1_assessment_entry_where = join(":", map {$arg1_assessment_entry->get("WHERE")->{$_}} qw(FILENAME LINENUM));
  my $arg2_assessment_entry = $store->{ENTRY_BY_KEY}{$arg2_key};
  my $arg2_assessment_entry_where = join(":", map {$arg2_assessment_entry->get("WHERE")->{$_}} qw(FILENAME LINENUM));
  die "arg1 subject ec is not blank:\n" . $arg1_assessment_entry_where
    unless ($arg1_assessment_entry->get("SUBJECT_FQEC") eq "" || $arg1_assessment_entry->get("SUBJECT_FQEC") =~ /^NILR\d+$/);
  die "arg2 subject ec is not blank:\n" . $arg2_assessment_entry_where
    unless ($arg2_assessment_entry->get("SUBJECT_FQEC") eq "" || $arg2_assessment_entry->get("SUBJECT_FQEC") =~ /^NILR\d+$/);
  my $ec = relation_entry_to_ec($entry, $arg1_assessment_entry, $arg2_assessment_entry);
  $arg1_assessment_entry->set("SUBJECT_FQEC", $ec);
  $arg2_assessment_entry->set("SUBJECT_FQEC", $ec);
}

foreach my $filename(sort keys %{$store->{ENTRY_BY_FILEANDLINE}}) {
  open($program_output, ">:utf8", $filename);
  foreach my $linenum(sort {$a<=>$b} keys %{$store->{ENTRY_BY_FILEANDLINE}{$filename}}) {
    my $entry = $store->{ENTRY_BY_FILEANDLINE}{$filename}{$linenum};
    $entry->set("LINE_CORRECTED", join("\t", map {$entry->get($_)} @{$entry->get("HEADER")->get("ELEMENTS")}));
    $logger->record_debug_information("CORRECTED_ENTRY", "\nLINE_READ=" . $entry->get("LINE"), "\nLINE_CORRECTED=" . $entry->get("LINE_CORRECTED"), $entry->get("WHERE"));
    print $program_output $entry->get("LINE_CORRECTED"), "\n";
  }
  close($program_output);
}

foreach my $key(keys %{$relation_ecs}) {
  my $value = $relation_ecs->{$key};
  $logger->record_debug_information("RELATION_EC", $key, $value, "NO_SOURCE");
}

my ($num_errors, $num_warnings) = $logger->report_all_information();

unless($switches->get('error_file') eq "STDERR") {
  print STDERR "Problems encountered (warnings: $num_warnings, errors: $num_errors)\n" if ($num_errors || $num_warnings);
  print STDERR "No warnings encountered.\n" unless ($num_errors || $num_warnings);
}

print $error_output ($num_warnings || 'No'), " warning", ($num_warnings == 1 ? '' : 's'), " encountered.\n";
exit 0;