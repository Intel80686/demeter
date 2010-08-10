package  Demeter::UI::Artemis::History;

=for Copyright
 .
 Copyright (c) 2006-2010 Bruce Ravel (bravel AT bnl DOT gov).
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

use strict;
use warnings;
use Cwd;
use List::Util qw(max);
use List::MoreUtils qw(minmax);

use Wx qw( :everything );
use Wx::Event qw(EVT_CLOSE EVT_LISTBOX EVT_CHECKLISTBOX EVT_BUTTON EVT_RADIOBOX
		 EVT_ENTER_WINDOW EVT_LEAVE_WINDOW EVT_CHOICE);
use base qw(Wx::Frame);

my @font      = (9, wxTELETYPE, wxNORMAL, wxNORMAL, 0, "" );
my @bold      = (9, wxTELETYPE, wxNORMAL,   wxBOLD, 0, "" );
my @underline = (9, wxTELETYPE, wxNORMAL, wxNORMAL, 1, "" );

sub new {
  my ($class, $parent) = @_;
  my $this = $class->SUPER::new($parent, -1, "Artemis [History]",
				wxDefaultPosition, wxDefaultSize,
				wxMINIMIZE_BOX|wxCAPTION|wxSYSTEM_MENU|wxCLOSE_BOX);
  EVT_CLOSE($this, \&on_close);
  $this->{statusbar} = $this->CreateStatusBar;
  $this->{statusbar} -> SetStatusText(q{});

  my $box = Wx::BoxSizer->new( wxHORIZONTAL );

  my $left = Wx::BoxSizer->new( wxVERTICAL );
  $box -> Add($left, 1, wxGROW|wxALL, 5);

  my $listbox       = Wx::StaticBox->new($this, -1, 'Fit history', wxDefaultPosition, wxDefaultSize);
  my $listboxsizer  = Wx::StaticBoxSizer->new( $listbox, wxVERTICAL );

  $this->{list} = Wx::CheckListBox->new($this, -1, wxDefaultPosition, [125,500],
				   [], wxLB_SINGLE);
  $listboxsizer -> Add($this->{list}, 0, wxALL, 0);
  $left -> Add($listboxsizer, 0, wxALL, 5);
  EVT_LISTBOX($this, $this->{list}, sub{OnSelect(@_)} );
  EVT_CHECKLISTBOX($this, $this->{list}, sub{OnCheck(@_), $_[1]->Skip} );

  $this->{all} = Wx::Button->new($this, -1, 'Select all');
  $left -> Add($this->{all}, 0, wxGROW|wxALL, 1);
  $this->{none} = Wx::Button->new($this, -1, 'Select none');
  $left -> Add($this->{none}, 0, wxGROW|wxALL, 1);
  EVT_BUTTON($this, $this->{all},  sub{mark(@_, 'all')});
  $this-> mouseover('all', "Mark all fits.");
  EVT_BUTTON($this, $this->{none}, sub{mark(@_, 'none')});
  $this-> mouseover('none', "Unmark all fits.");

  $this->{close} = Wx::Button->new($this, wxID_CLOSE, q{}, wxDefaultPosition, wxDefaultSize);
  $left -> Add($this->{close}, 0, wxGROW|wxLEFT, 1);
  EVT_BUTTON($this, $this->{close}, \&on_close);
  $this-> mouseover('close', "Hide the history window.");

  my $right = Wx::BoxSizer->new( wxVERTICAL );
  $box -> Add($right, 0, wxGROW|wxALL, 5);

  my $nb  = Wx::Notebook->new($this, -1, wxDefaultPosition, wxDefaultSize, wxNB_TOP);
  $right -> Add($nb, 1, wxGROW|wxALL, 0);

  my $logpage = Wx::Panel->new($nb, -1);
  my $logbox  = Wx::BoxSizer->new( wxHORIZONTAL );
  $logpage->SetSizer($logbox);

  my $reportpage = Wx::Panel->new($nb, -1);
  my $reportbox  = Wx::BoxSizer->new( wxVERTICAL );
  $reportpage->SetSizer($reportbox);

  my $actionspage = Wx::Panel->new($nb, -1);
  my $actionsbox  = Wx::BoxSizer->new( wxHORIZONTAL );
  $actionspage->SetSizer($actionsbox);

  ## -------- text box for log file
  $this->{log} = Wx::TextCtrl->new($logpage, -1, q{}, wxDefaultPosition, [550, -1],
				   wxTE_MULTILINE|wxTE_READONLY|wxHSCROLL);
  $this->{log} -> SetFont( Wx::Font->new( 9, wxTELETYPE, wxNORMAL, wxNORMAL, 0, "" ) );
  $logbox -> Add($this->{log}, 1, wxGROW|wxALL, 5);

  $this->{normal}     = Wx::TextAttr->new(Wx::Colour->new('#000000'), wxNullColour, Wx::Font->new( @font ) );
  $this->{happiness}  = Wx::TextAttr->new(Wx::Colour->new('#acacac'), wxNullColour, Wx::Font->new( @font ) );
  $this->{parameters} = Wx::TextAttr->new(Wx::Colour->new('#000000'), wxNullColour, Wx::Font->new( @underline ) );
  $this->{header}     = Wx::TextAttr->new(Wx::Colour->new('#000055'), wxNullColour, Wx::Font->new( @bold ) ); # '#8B4726'
  $this->{data}       = Wx::TextAttr->new(Wx::Colour->new('#ffffff'), Wx::Colour->new('#000055'), Wx::Font->new( @bold ) );

  ## -------- controls for writing reports on fits
  my $controls = Wx::BoxSizer->new( wxHORIZONTAL );
  $reportbox -> Add($controls, 0, wxGROW|wxALL, 0);
  $this->{summarize} = Wx::Button->new($reportpage, -1, "Sumarize marked fits");
  $controls->Add($this->{summarize}, 1, wxALL, 5);
  EVT_BUTTON($this, $this->{summarize}, sub{summarize(@_)});
  $this-> mouseover('summarize', "Write a short summary of each marked fit.");

  my $repbox      = Wx::StaticBox->new($reportpage, -1, 'Report on a parameter', wxDefaultPosition, wxDefaultSize);
  my $repboxsizer = Wx::StaticBoxSizer->new( $repbox, wxVERTICAL );
  $reportbox -> Add($repboxsizer, 0, wxGROW|wxALL, 5);

  $controls = Wx::BoxSizer->new( wxHORIZONTAL );
  $repboxsizer -> Add($controls, 0, wxGROW|wxALL, 5);
  my $label = Wx::StaticText->new($reportpage, -1, "Select parameter: ");
  $controls->Add($label, 0, wxALL, 7);
  $this->{params} = Wx::Choice->new($reportpage, -1, wxDefaultPosition, wxDefaultSize, ["Statistcal parameters"]);
  $controls->Add($this->{params}, 0, wxALL, 5);
  EVT_CHOICE($this, $this->{params}, sub{write_report(@_)});
  $this-> mouseover('params', "Write and plot a report on the statistical parameters or on the chosen fitting parameter.");

  $this->{doreport} = Wx::Button->new($reportpage, -1, "Write report");
  $controls->Add($this->{doreport}, 0, wxALL, 5);
  EVT_BUTTON($this, $this->{doreport}, sub{write_report(@_)});
  $this-> mouseover('doreport', "Write and plot a report on the statistical parameters or on the chosen fitting parameter.");

  $controls = Wx::BoxSizer->new( wxHORIZONTAL );
  $repboxsizer -> Add($controls, 0, wxGROW|wxALL, 5);
  $this->{plotas} = Wx::RadioBox->new($reportpage, -1, "Plot statistics using", wxDefaultPosition, wxDefaultSize,
				      ["Reduced chi-square", "R-factor", "Happiness"],
				      1, wxRA_SPECIFY_ROWS);
  $controls->Add($this->{plotas}, 0, wxALL, 0);
  $this-> mouseover('plotas', "Specify which column will be plotted after generating a statistics report.");

  $controls = Wx::BoxSizer->new( wxHORIZONTAL );
  $repboxsizer -> Add($controls, 0, wxGROW|wxALL, 5);
  $this->{showy} = Wx::CheckBox->new($reportpage, -1, "Show y=0");
  $controls->Add($this->{showy}, 0, wxALL, 0);
  $this-> mouseover('showy', "Check this button to force the report plot to scale the plot such that the y axis starts at 0");

  $this->{report} = Wx::TextCtrl->new($reportpage, -1, q{}, wxDefaultPosition, [550, -1],
				   wxTE_MULTILINE|wxTE_READONLY|wxHSCROLL);
  $this->{report} -> SetFont( Wx::Font->new( 9, wxTELETYPE, wxNORMAL, wxNORMAL, 0, "" ) );
  $reportbox -> Add($this->{report}, 1, wxGROW|wxALL, 5);

  $controls = Wx::BoxSizer->new( wxHORIZONTAL );
  $reportbox -> Add($controls, 0, wxGROW|wxALL, 0);
  $this->{savereport} = Wx::Button->new($reportpage, -1, "Save report");
  $controls->Add($this->{savereport}, 1, wxALL, 5);
  EVT_BUTTON($this, $this->{savereport}, sub{savereport(@_)});
  $this-> mouseover('savereport', "Save the report contents to a file.");


  ## -------- actions on selected fit
  my $actionsleft = Wx::BoxSizer->new( wxVERTICAL );
  my $actionsright = Wx::BoxSizer->new( wxVERTICAL );
  $actionsbox->Add($actionsleft,  1, wxGROW|wxALL, 10);
  $actionsbox->Add($actionsright, 1, wxGROW|wxALL, 10);

  $label = Wx::StaticText->new($actionspage, -1, "Actions on the selected fit");
  $label -> SetFont( Wx::Font->new( 12, wxDEFAULT, wxNORMAL, wxBOLD, 0, "" ) );
  $actionsleft->Add($label, 0, wxGROW|wxALL, 10);
  $this->{restore} = Wx::Button->new($actionspage, -1, "Restore selected fit");
  $actionsleft->Add($this->{restore}, 0, wxGROW|wxALL, 5);
  $this->{savelog} = Wx::Button->new($actionspage, -1, "Save log file from selected fit");
  $actionsleft->Add($this->{savelog}, 0, wxGROW|wxALL, 5);
  $this->{export} = Wx::Button->new($actionspage, -1, "Export selected fit");
  $actionsleft->Add($this->{export}, 0, wxGROW|wxALL, 5);
  $this->{discard} = Wx::Button->new($actionspage, -1, "Discard selected fit");
  $actionsleft->Add($this->{discard}, 0, wxGROW|wxALL, 5);

  EVT_BUTTON($this, $this->{restore}, sub{restore(@_)});
  $this-> mouseover('restore', "Restore the fitting model from the selected fit as the active fitting model.");
  EVT_BUTTON($this, $this->{savelog}, sub{savelog(@_)});
  $this-> mouseover('savelog', "Save the log file from the selected fit.");
  EVT_BUTTON($this, $this->{export},  sub{export(@_)});
  $this-> mouseover('export', "Save a project file containing only this fit and no history.");
  EVT_BUTTON($this, $this->{discard}, sub{discard(@_, 'selected')});
  $this-> mouseover('discard', "Discard the selected fit from this project.");

  $label = Wx::StaticText->new($actionspage, -1, "Actions on the marked fits");
  $label -> SetFont( Wx::Font->new( 12, wxDEFAULT, wxNORMAL, wxBOLD, 0, "" ) );
  $actionsright->Add($label, 0, wxGROW|wxALL, 10);
  $this->{discardm} = Wx::Button->new($actionspage, -1, "Discard marked fits");
  $actionsright->Add($this->{discardm}, 0, wxGROW|wxALL, 5);

  EVT_BUTTON($this, $this->{discardm},  sub{discard(@_, 'marked')});
  $this->mouseover('discardm', "Discard all marked fits from this project.");


  $nb -> AddPage($logpage,     "Log file", 1);
  $nb -> AddPage($reportpage,  "Reports", 0);
  $nb -> AddPage($actionspage, "Actions", 0);

  $this->SetSizerAndFit($box);
  return $this;
};

sub mouseover {
  my ($self, $widget, $text) = @_;
  EVT_ENTER_WINDOW($self->{$widget}, sub{$self->{statusbar}->PushStatusText($text); $_[1]->Skip});
  EVT_LEAVE_WINDOW($self->{$widget}, sub{$self->{statusbar}->PopStatusText if ($self->{statusbar}->GetStatusText eq $text); $_[1]->Skip});
};

sub OnSelect {
  my ($self, $event) = @_;
  my $fit = $self->{list}->GetClientData($self->{list}->GetSelection);
  $self->put_log($fit->logtext, $fit->color);
  $self->set_params($fit);
};
sub OnCheck {
  #print "check: ", join(" ", @_), $/;
  1;
};

sub mark {
  my ($self, $event, $how) = @_;
  foreach my $i (0 .. $self->{list}->GetCount-1) {
    my $onoff = ($how eq 'all') ? 1 : 0;
    $self->{list}->Check($i, $onoff);
  };
};

sub on_close {
  my ($self) = @_;
  $self->Show(0);
  $self->GetParent->{toolbar}->ToggleTool(3, 0);
};


sub put_log {
  my ($self, $text, $color) = @_;
  my $busy = Wx::BusyCursor->new();
  $self -> {log} -> SetValue(q{});
  my $max = 0;
  foreach my $line (split(/\n/, $text)) {
    $max = max($max, length($line));
  };
  my $pattern = '%-' . $max . 's';
  $self->{stats} = Wx::TextAttr->new(Wx::Colour->new('#000000'), Wx::Colour->new($color), Wx::Font->new( @font ) );

  foreach my $line (split(/\n/, $text)) {
    my $was = $self -> {log} -> GetInsertionPoint;
    $self -> {log} -> AppendText(sprintf($pattern, $line) . $/);
    my $is = $self -> {log} -> GetInsertionPoint;

    my $color = ($line =~ m{(?:parameters|variables):})                     ? 'parameters'
              : ($line =~ m{(?:Happiness|semantic|NEVER|a penalty of|Penalty of)}) ? 'happiness'
              : ($line =~ m{\A(?:R-factor|Reduced)})                        ? 'stats'
              : ($line =~ m{\A(?:=+\s+Data set)})                           ? 'data'
              : ($line =~ m{\A (?:Name|Description|Figure|Time|Environment|Interface|Prepared|Contact)}) ? 'header'
              : ($line =~ m{\A\s+\.\.\.})                                   ? 'header'
	      :                                                               'normal';
    $color = 'normal' if ((not $Demeter::UI::Artemis::demeter->co->default("artemis", "happiness"))
			  and ($color eq 'stats'));
    $self->{log}->SetStyle($was, $is, $self->{$color});
  };
  $self->{log}->ShowPosition(0);
  #$self->{save}->Enable(1);
  undef $busy;
};

sub set_params {
  my ($self, $fit) = @_;
  $self->{params}->Clear;
  $self->{params}->Append('Statistcal parameters');
  foreach my $g (sort {$a->name cmp $b->name} @{$fit->gds}) {
    $self->{params}->Append($g->name);
  };
  $self->{params}->SetStringSelection('Statistcal parameters');
};

sub mark_all_if_none {
  my ($self) = @_;
  my $count = 0;
  foreach my $i (0 .. $self->{list}->GetCount-1) {
    ++$count if $self->{list}->IsChecked($i);
  };
  $self->mark(q{}, 'all') if (not $count);
};

sub write_report {
  my ($self, $event) = @_;
  $self->mark_all_if_none;

  ## -------- generate report and enter it into text box
  $self->{report}->Clear;
  my $param = $self->{params}->GetStringSelection;
  if ($param eq 'Statistcal parameters') {
    $self->{report}->AppendText($Demeter::UI::Artemis::demeter->template('fit', 'report_head_stats'));
  } else {
    $self->{report}->AppendText($Demeter::UI::Artemis::demeter->template('fit', 'report_head_param'));
  };
  my @x = ();
  foreach my $i (0 .. $self->{list}->GetCount-1) {
    next if not $self->{list}->IsChecked($i);
    my $fit = $self->{list}->GetClientData($i);
    push @x, $fit->fom;
    if ($param eq 'Statistcal parameters') {
      $self->{report}->AppendText($fit->template('fit', 'report_stats'));
    } else {
      my $g = $fit->fetch_gds($param);
      next if not $g;
      $fit->mo->fit($fit);
      $self->{report}->AppendText($g->template('fit', 'report_param', {param=>$param}));
      $fit->mo->fit(q{});
    };
  };

  ## -------- plot!
  my ($xmin, $xmax) = minmax(@x);
  my $delta = ($xmax-$xmin)/5;
  ($xmin, $xmax) = ($xmin-$delta, $xmax+$delta);
  $Demeter::UI::Artemis::demeter->po->start_plot;
  my $tempfile = $Demeter::UI::Artemis::demeter->po->tempfile;
  open my $T, '>'.$tempfile;
  print $T $self->{report}->GetValue;
  close $T;
  if ($param eq 'Statistcal parameters') {
    my $col = $self->{plotas}->GetSelection + 2;
    $Demeter::UI::Artemis::demeter->dispose($Demeter::UI::Artemis::demeter->template('plot', 'plot_stats', {file=>$tempfile, xmin=>$xmin, xmax=>$xmax, col=>$col, showy=>$self->{showy}->GetValue}), 'plotting');
  } else {
    $Demeter::UI::Artemis::demeter->dispose($Demeter::UI::Artemis::demeter->template('plot', 'plot_file', {file=>$tempfile, xmin=>$xmin, xmax=>$xmax, param=>$param, showy=>$self->{showy}->GetValue}), 'plotting');
  };
  $self->status("Reported on $param");
};

sub summarize {
  my ($self, $event) = @_;
  $self->mark_all_if_none;
  my $text = q{};
  foreach my $i (0 .. $self->{list}->GetCount-1) {
    next if not $self->{list}->IsChecked($i);
    my $fit = $self->{list}->GetClientData($i);
    $text .= $fit -> summary;
  };
  return if (not $text);
  $self->{report}->Clear;
  $self->{report}->SetValue($text)
};
sub savereport {
  my ($self, $event) = @_;
  my $fd = Wx::FileDialog->new( $self, "Save log file", cwd, "report.txt",
				"Text files (*.txt)|*.txt",
				wxFD_SAVE|wxFD_CHANGE_DIR|wxFD_OVERWRITE_PROMPT,
				wxDefaultPosition);
  if ($fd->ShowModal == wxID_CANCEL) {
    $self->status("Not saving report.");
    return;
  };
  my $fname = File::Spec->catfile($fd->GetDirectory, $fd->GetFilename);
  open my $R, '>', $fname;
  print $R $self->{report}->GetValue;
  close $R;
  $self->status("Wrote report to '$fname'.");
};

sub restore {
  my ($self, $event) = @_;
  $self->status("restore this fit...");
};

sub discard {
  my ($self, $event, $how) = @_;
  $self->status("discard $how fit(s)...");
};

sub savelog {
  my ($self, $event) = @_;
  my $fit = $self->{list}->GetClientData($self->{list}->GetSelection);

  (my $pref = $fit->name) =~ s{\s+}{_}g;
  my $fd = Wx::FileDialog->new( $self, "Save log file", cwd, $pref.q{.log},
				"Log files (*.log)|*.log",
				wxFD_SAVE|wxFD_CHANGE_DIR|wxFD_OVERWRITE_PROMPT,
				wxDefaultPosition);
  if ($fd->ShowModal == wxID_CANCEL) {
    $self->status("Not saving log file.");
    return;
  };
  my $fname = File::Spec->catfile($fd->GetDirectory, $fd->GetFilename);
  $fit->logfile($fname);
  $self->status("Wrote log file to '$fname'.");
};

sub export {
  my ($self, $event) = @_;
  $self->status("export this fit...");
};


1;


=head1 NAME

Demeter::UI::Artemis::History - A fit history interface for Artemis

=head1 VERSION

This documentation refers to Demeter version 0.4.

=head1 SYNOPSIS

Examine past fits contained in the fitting project.

=head1 CONFIGURATION


=head1 DEPENDENCIES

Demeter's dependencies are in the F<Bundle/DemeterBundle.pm> file.

=head1 BUGS AND LIMITATIONS

=over 4

=item *

Move fits into the plotting list for overplotting data with multiple
fits

=item *

Restore a fitting model

=item *

Discard one or more fits, completely removing them from the project
and the order file.

=item *

Export selected fit to a project file.  This contains the model of the
selected fit without the history.  Useful for bug reports and other
communications.

=item *

Calculations on the report tab: average, Einstein

=back

Please report problems to Bruce Ravel (bravel AT bnl DOT gov)

Patches are welcome.

=head1 AUTHOR

Bruce Ravel (bravel AT bnl DOT gov)

L<http://cars9.uchicago.edu/~ravel/software/>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006-2010 Bruce Ravel (bravel AT bnl DOT gov). All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlgpl>.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut
