package Demeter::Data::JSON;

=for Copyright
 .
 Copyright (c) 2006-2018 Bruce Ravel (http://bruceravel.github.io/home).
 All rights reserved.
 .
 This file is free software; you can redistribute it and/or
 modify it under the same terms as Perl itself. See The Perl
 Artistic License.
 .
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut

use autodie qw(open close);

use Moose;
extends 'Demeter';
use MooseX::Aliases;
use Demeter::StrTypes qw( FileName );

#use diagnostics;
use Carp;
use Compress::Zlib;
use File::Basename;
use File::Spec;
use JSON;
use List::Util qw(max);
use List::MoreUtils qw(any none);


has 'file'    => (is => 'rw', isa => FileName,  default => q{},
		  trigger => sub{shift -> Read} );
has 'decoded' => (is => 'rw', isa => 'HashRef');
has 'entries' => (
		  traits    => ['Array'],
		  is        => 'rw',
		  isa       => 'ArrayRef[ArrayRef]',
		  default   => sub { [] },
		  handles   => {
				'add_entry' => 'push',
				'remove_entry'  => 'pop',
				'clear_entries' => 'clear',
			       }
		 );
has 'n'       => (is => 'rw', isa => 'Int',  default => 0);
has 'journal' => (is => 'rw', isa => 'Str',  default => q{},);
has 'lcf'     => (is => 'rw', isa => 'HashRef',  default => sub{ {} },);
has 'pca'     => (is => 'rw', isa => 'HashRef',  default => sub{ {} },);
has 'peakfit' => (is => 'rw', isa => 'HashRef',  default => sub{ {} },);
has 'lineshapes' => (
		     traits    => ['Array'],
		     is        => 'rw',
		     isa       => 'ArrayRef[ArrayRef]',
		     default   => sub { [] },
		     handles   => {
				   'add_lineshape' => 'push',
				   'remove_lineshape'  => 'pop',
				   'clear_lineshape' => 'clear',
				  }
		    );


sub BUILD {
  my ($self, @params) = @_;
  $self->mo->push_JSON($self);
};

sub Read {
  my ($self) = @_;
  my $file = $self->file;
  return 0 if not $file;
  if (not -e $file) {
    carp(ref($self) . ": $file does not exist\n\n");
    return -1;
  };
  if (not -r $file) {
    carp(ref($self) . ": $file cannot be read (permissions?)\n\n");
    return -1;
  };

  my @entries = ();
  my $athena_fh = gzopen($file, "rb") or die "could not open $file as an Athena project\n";
  my $stash = File::Spec->catfile(Demeter->stash_folder, basename($self->file));
  my $line;
  open(my $S, ">", $stash);
  while ($athena_fh->gzreadline($line) > 0) {
    print $S $line;
  };
  $athena_fh->gzclose();
  close $S;

  $self->decoded(decode_json(Demeter->slurp($stash)));
  $self->n($#{$self->decoded->{_____order}} + 1);
  $self->journal(join($/, @{$self->decoded->{_____journal}})) if exists $self->decoded->{_____journal};
  $self->lcf    ({%{$self->decoded->{_____lcf}}})     if exists $self->decoded->{_____lcf};
  $self->pca    ({%{$self->decoded->{_____pca}}})     if exists $self->decoded->{_____pca};
  $self->peakfit({%{$self->decoded->{_____peakfit}}}) if exists $self->decoded->{_____peakfit};
  my $count = 0;
  while (exists $self->decoded->{'_____lineshape'.$count}) {
    my %ls = %{$self->decoded->{'_____lineshape'.$count}};
    my @ls = %ls;
    $self->add_lineshape(\@ls);
    $count++;
  };

  unlink $stash;
  #print join("|", @{$self->decoded->{_____order}}), $/;
};



sub list {
  my ($self, @attributes) = @_;
  my $response  = q{};
  my $length    = 0;
  my @rows;

  ## slurp up record labels and optional attributes
  foreach my $group (@{ $self->decoded->{_____order} }) {
    my %args = %{ $self->decoded->{$group}->{args} };
    $length = max($length, length($args{label}));
    push @rows, [$args{label}, @args{@attributes}];
  };
  $length += 3;

  ## header
  my $pattern = "#\t     %-" . $length . 's';
  $response .=  sprintf $pattern, 'record';
  foreach my $att (@attributes) {
    $response .= sprintf "%-15s", $att;
  };
  $response .= "\n# " . '-' x 60 . "\n";

  ## list
  $pattern = "\t%2d : %-" . $length . 's';
  my $i = 0;
  foreach my $row (@rows) {
    $response .= sprintf $pattern, ++$i, $row->[0];
    my $j = 1;
    foreach my $att (@attributes) {
      $response .= sprintf "%-15s", $row->[$j++];
    };
    $response .= "\n";
  };
  return $response;
};

sub allnames {
  my ($self, $notxanes) = @_;
  my @names;
  ## slurp up record labels
  foreach my $group (@{ $self->decoded->{_____order} }) {
    my %args = %{ $self->decoded->{$group}->{args} };
    next if ($notxanes and ($args{datatype} =~ m{(?:detector|background|xanes)}));
    push @names, $args{label};
  };
  return @names;
};
sub plot_as_chi {
  my ($self, $noxanes) = @_;
  my (@names, @entries, @positions);
  ## slurp up record labels and optional attributes
  my $pos = -1;
  foreach my $group (@{ $self->decoded->{_____order} }) {
    ++$pos;
    my %args = %{ $self->decoded->{$group}->{args} };
    next if ($args{datatype} and ($args{datatype} =~ m{(?:detector|background|xanes)}));
    next if $args{is_xanes};
    next if $args{not_data};
    push @names, $args{label};
    push @entries, $group;
    push @positions, $pos;
  };
  return \@names, \@entries, \@positions;
};


sub slurp {
  my ($self) = @_;
  my @groups = @{ $self->decoded->{_____order} };
  my @data = $self->record(1 .. $#groups+1);
  return @data;
};
alias prj => 'slurp';


sub record {
  my ($self, @entries) = @_;
  #Demeter->trace;
  my @groups = ();
  my @which = map { ($_ =~ m{(\d+)\-(\d+)}) ? ($1 .. $2) : $_ } @entries;
  foreach my $g (@which) {
    next if ($g > $self->n);
    my $gg = $g-1;
    my $group = $self->decoded->{_____order}->[$gg];
    my $rec = $self->_record( $group );
    $rec->prjrecord(join(", ", $self->file, $g));
    $rec->provenance(sprintf("Athena project file %s, record %d", $self->file, $g));

    my $array = ($rec->datatype =~ m{(?:xmu|xanes)}) ? 'energy'
              : ($rec->datatype eq 'chi')            ? 'k'
	      :                                        'energy';
    my @x = $rec->get_array($array); # set things for about dialog
    if (@x) {
      push @groups, $rec;
      $rec->npts($#x+1);
      $rec->xmin($x[0]);
      $rec->xmax($x[$#x]);
    } else {
      $rec->DEMOLISH;
    };
  };
  return (wantarray) ? @groups : $groups[0];
};
alias records => 'record';



sub _record {
  my ($self, $group) = @_;
  my %args   = %{ $self->decoded->{$group}->{args} };
  my @x      = @{ $self->decoded->{$group}->{x} };
  my @y      = @{ $self->decoded->{$group}->{y} };
  my @i0     = exists($self->decoded->{$group}->{i0})     ? @{ $self->decoded->{$group}->{i0} }     : ();
  my @signal = exists($self->decoded->{$group}->{signal}) ? @{ $self->decoded->{$group}->{signal} } : ();
  my @std    = exists($self->decoded->{$group}->{stddev}) ? @{ $self->decoded->{$group}->{stddev} } : ();
  my @xdi    = exists($self->decoded->{$group}->{xdi})    ? @{ $self->decoded->{$group}->{xdi} }    : ();
  my ($i0_scale, $signal_scale, $is_merge) = (0,0,0);

  ## this allows you to import the same data group twice without a
  ## groupname collision.
  my $collided = 0;
  if (Demeter->mo->any($group)) {
    $group = $self->_get_group;
    $collided  = 1;
  };
  my $data = Demeter::Data->new(group	    => $group,
				from_athena => 1,
				collided    => $collided,
			       );
  $data->dispense('process','make_group');
  my ($xsuff, $ysuff) = ($args{is_xmu}) ? qw(energy xmu) : qw(k chi);
  $self->place_array(join('.', $group, $xsuff), \@x);
  $self->place_array(join('.', $group, $ysuff), \@y);
  if (@i0) {
    $self->place_array(join('.', $group, 'i0'), \@i0);
    $i0_scale = max(@y) / max(@i0);
  };
  if (@signal) {
    $self->place_array(join('.', $group, 'signal'), \@signal);
    $signal_scale = max(@y) / max(@signal);
  };
  if (@std) {
    $self->place_array(join('.', $group, 'stddev'), \@std);
    $is_merge = 1;
  };
  my $quenched_state = 0;
  my %groupargs = ();
  foreach my $k (keys %args) {
    next if any { $k eq $_ } qw(
				 bindtag deg_tol denominator detectors
				 en_str file frozen line mu_str
				 numerator old_group original_label
				 peak refsame not_data
				 bkg_switch bkg_switch2
				 is_xmu is_chi is_xanes is_xmudat
				 bkg_stan_lab bkg_flatten_was
				 bkg_fnorm
			      );
    ## clean up from old implementation(s) of XDI
    next if any { $k eq $_ } qw(
				 xdi_mu_reference  xdi_ring_current  xdi_abscissa            xdi_start_time
				 xdi_crystal       xdi_focusing      xdi_mu_transmission     xdi_ring_energy
				 xdi_collimation   xdi_d_spacing     xdi_undulator_harmonic  xdi_mu_fluorescence
				 xdi_end_time      xdi_source        xdi_edge_energy         xdi_harmonic_rejection

				 xdi_mono xdi_sample xdi_scan xdi_extensions xdi_applications
				 xdi_labels xdi_detector xdi_beamline xdi_column xdi_comments xdi_version
				 xdi_facility
			      );
  SWITCH: {
      ($k eq 'quenched') and do {
	$quenched_state = $args{$k}; # take care to set this at the very end
	last SWITCH;
      };
      ($k =~ m{\A(?:lcf|peak|lr)}) and do {
	last SWITCH;
      };
      ($k eq 'titles') and do {
	$groupargs{titles} = $args{titles};
	last SWITCH;
      };
      ($k eq 'reference') and do {
	$groupargs{referencegroup} = $args{reference};
	last SWITCH;
      };
      ($k =~ m{\A(?:project_)?marked\z}) and do { # mark indicator in old or new Athena project file
	$groupargs{marked} = $args{$k};
	last SWITCH;
      };
      ($k eq 'importance') and do {
	$groupargs{importance} = $args{importance};
	last SWITCH;
      };
      ($k eq 'i0') and do {
	$groupargs{i0_string} = $args{i0};
	last SWITCH;
      };
      ($k eq 'signal') and do {
	$groupargs{signal_string} = $args{signal};
	last SWITCH;
      };
      (any {$k eq $_} qw(i0_string signal_string numerator denominator referencegroup source)) and do {
	$groupargs{$k} = $args{$k};
	last SWITCH;
      };
      ($k eq 'label') and do {
	$groupargs{$k} = $args{$k};
	last SWITCH;
      };
      #($k eq 'xdi_beamline') and do {
      #  $groupargs{$k} = {name => $args{$k}} if $args{$k};
      #  last SWITCH;
      #};

      ## back Fourier transform parameters
      ($k =~ m{\Abft_(.*)\z}) and do { # bft_win --> bft_rwindow, others are the same
	my $which = $1;
	($which = 'rwindow') if ($1 eq 'win');
	$groupargs{'bft_'.$which} = $args{$k};
	last SWITCH;
      };

      ## forward Fourier transform parameters
      ($k =~ m{\Afft_(.*)\z}) and do { # fft_win --> fft_rwindow, others are the same
	my $which = $1;
	last SWITCH if ($which eq 'kw');
	($which = 'kwindow') if ($1 eq 'win');
	if ($1 eq 'arbkw') {
	  ## do nothing with arb kw from project -- for now
	  1;
	  #$groupargs{fit_karb} = ($args{fft_arbkw}) ? 1 : 0;
	  #$groupargs{fit_karb_value} = $args{$k};
	} else {
	  $groupargs{'fft_'.$which} = $args{$k};
	};
	last SWITCH;
      };

      ## plotting parameters
      ($k =~ m{\Aplot_(.*)\z}) and do {
	if ($1 eq 'yoffset') {
	  $groupargs{'y_offset'} = $args{$k};
	} elsif ($1 eq 'scale') {
	  $groupargs{plot_multiplier} = $args{$k};
	};
	last SWITCH;
      };

      ## background and normalization parameters
      ($k =~ m{\Abkg_(.*)\z}) and do { # bft_win --> bft_rwindow, others are the same
	my $which = $1;
	($which = 'kwindow') if ($1 eq 'win');
	if (($1 =~ m{clamp[12]}) and ($args{$k} !~ m{\A\+?[0-9]+\z})) {
	  $args{$k} = $data->clamp(lc($args{$k}));
	};
	$groupargs{'bkg_'.$which} = $args{$k};
	last SWITCH;
      };

      ## is_* parameters (merge chi nor xmu xmudat xanes) = ok
      ($k =~ m{\Ais_(.*)\z}) and do {
	if (none { $1 eq $_} qw(bkg diff pixel proj qsp raw rec ref rsp)) {
	  $groupargs{$k} = $args{$k};
	};
	last SWITCH;
      };

      ## xdi_ parameters
      # ($k =~ m{\Axdi_(.*)\z}) and do {
      # 	$groupargs{$k} = $args{$k};
      # 	last SWITCH;
      # };

      ## skip all parameters that will be generated as Athena proceeds (including the possibly ro xdifile)
      #do {
      #  print $k, $/;
      #};

    };
  };

  $groupargs{name} = $groupargs{label} || q{};
  delete $groupargs{label};
  $groupargs{fft_pc}   = ($args{fft_pc} eq 'None') ? 0 : 0;
  $groupargs{datatype} = ($args{is_xmu})    ? 'xmu'
                       : ($args{is_chi})    ? 'chi'
                       : ($args{is_xmudat}) ? 'xmudat'
		       :                      q{};
  $groupargs{datatype} = 'xanes' if ($args{is_xanes});
  $groupargs{i0_scale}       = $i0_scale;
  $groupargs{signal_scale}   = $signal_scale;
  $groupargs{is_merge}       = $args{is_merge};
  $groupargs{update_data}    = 0;
  $groupargs{update_columns} = 0;
  $groupargs{update_norm}    = 1 if (not $args{is_chi});
  $groupargs{update_fft}     = 1 if ($args{is_chi});
  if ($groupargs{referencegroup}) {
    my $ref = $data->mo->fetch('Data', $groupargs{referencegroup});
    $data->reference($ref);
  };
  $data -> set(%groupargs);
  my $command = $data->template("process", "deriv");
  $data->dispose($command);
  $data->quenched($quenched_state);

  # if (Demeter->xdi_exists) {
  #   if (@xdi) {
  #     my $comments = $xdi->comments;
  #     $comments =~ s{\\n}{\n}g;	# unstringify newlines in comments (see D::D::Athena#148)
  #     $xdi->comments($comments);
  #     $data->xdi($xdi);
  #   } else {
  #     $data->xdi(Xray::XDI->new());
  #     $data -> xdi -> set_item('Element', 'edge',    uc($data->fft_edge));
  #     $data -> xdi -> set_item('Element', 'symbol',  ucfirst(lc($data->bkg_z)));
  #   };
  # };

  return $data;
}





__PACKAGE__->meta->make_immutable;
1;


=head1 NAME

Demeter::Data::JSON - Read data from JSON-style Athena project files

=head1 VERSION

This documentation refers to Demeter version 0.9.26.

=head1 DESCRIPTION

This class contains methods for interacting with Athena project files.
It is not a subclass of some other Demeter method.

  $project   = Demeter::Data::JSON->new(file=>'some.prj');
  @data     = $project -> slurp;         # import all records
  ($d1, $2) = $project -> record(3, 8);  # import specific records

The script C<lsprj>, which comes with Demeter, uses this module.

See L<Demeter::Data::Athena> for Demeter's method of writing
Athena project files.

Note that the semantics of this object are identical to
Demeter::Data::Prj.  They are intended to be used interchangeably.
Athena and Artemis will read Prj and JSON files transparently.

This JSON file has some manditory structure to allow it to be used
properly by Athena and Artemis see L<some file...>.

=head1 METHODS

=head2 Accessor methods

=over 4

=item C<set>

Currently, the only thing to set is C<file>.

  $prj -> set(file=>'some.prj');

Setting the file triggers reading the file.  You do not need to read
the file explicitly.

=back

=head2 Project file methods

=over 4

=item C<slurp>

Return a list containing Demeter Data objects for each group from the
project file.  This is a convenience wrapper wround the C<record>
method.

  @data_objects = $prj -> slurp

C<prj> is an alias for C<slurp>.

=item C<record>

Import a single record from the project file.

To retrieve the third group from an Athena project file:

  $data_object = $prj -> record(3);

Note that, for this method, you count the groups in the Athena project
starting with 1, where record #1 is the top-most record in the list as
displayed in Athena.

C<records> is an alias for C<record>, as in

  @data_objects = $prj -> records(3, 4, 8);

All imported records will have attributes set to values imported from
the project file.

Note that is you pass this method an argument whose value is larger
than the number of records in the associated project file, it will
silently skip that argument.

=item C<list>

Return a listing of the labels of the groups in the project file.

  print $prj -> list;
   ==prints==>
    #     record
    # -------------------------------------------
      1 : Iron foil
      2 : Iron oxide
      3 : Iron sulfide

Optionally, a list of attributes can be passed, generating a simple
table of parameter values.

  print $prj -> list(qw(bkg_rbkg fft_kmin));
   ==prints==>
    #     record         bkg_rbkg   fft_kmin
    # -------------------------------------------
      1 : Iron foil      1.6        2.0
      2 : Iron oxide     1.0        2.0
      3 : Iron sulfide   1.0        3.0

The attributes are those for the L<Demeter::Data> object.

=item C<allnames>

This returns the labels as displayed in Athena's groups list as an array.

  my @names = $prj -> allnames;

=item C<plot_as_chi>

This returns the same sort of list as the C<entries> accessor, except
that all the gorups that cannot be plotted as chi(K) (i.e. detector
groups, xanes groups, etc) have been filtered out.  Two array
references are returned, the first containing the names of those
groups, the second containing the filtered entries list.

  my ($names_ref, $entries_ref) = $prj -> plot_as_chi;

=back

=head1 DIAGNOSTICS

=over 4

=item C<Demeter::Data::JSON: $file does not exist>

The Athena project file cannot be found on your computer.

=item C<Demeter::Data::JSON:$file cannot be read (permissions?)>

The specified Athena project file cannot be read by Demeter, possibly
because of permissions settings.

=item C<could not open $file as an Athena project>

A problem was encountered attempting to open the Athena project file
using the L<Compress::Zlib> module.

=back

=head1 CONFIGURATION

There are no configuration options for this class.

See L<Demeter::Config> for a description of Demeter's
configuration system.

=head1 DEPENDENCIES

Demeter's dependencies are in the F<Build.PL> file.

=head1 BUGS AND LIMITATIONS

=over 4

=item *

Not all Athena attributes are dealt with correctly yet -- title is the
biggie

=item *

Need to deal with chi groups, detector groups, etc.

=item *

Not dealing yet with, for instance, LCF parameters

=back

Please report problems to the Ifeffit Mailing List
(L<http://cars9.uchicago.edu/mailman/listinfo/ifeffit/>)

Patches are welcome.

=head1 AUTHOR

Bruce Ravel, L<http://bruceravel.github.io/home>

L<http://bruceravel.github.io/demeter/>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006-2018 Bruce Ravel (L<http://bruceravel.github.io/home>). All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlgpl>.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut
