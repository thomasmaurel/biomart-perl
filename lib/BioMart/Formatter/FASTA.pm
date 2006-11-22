# $Id$
#
# BioMart module for BioMart::Formatter::TXT
#
# You may distribute this module under the same terms as perl
# itself.

# POD documentation - main docs before the code.

=head1 NAME

BioMart::Formatter::FASTA

=head1 SYNOPSIS

The FASTA Formatter returns whitespace separated tabular data
for a BioMart query's ResultTable


=head1 DESCRIPTION

When given a BioMart::ResultTable containing the results of 
a BioMart::Query the FASTA Formatter will return tabular output
with one line for each row of data in the ResultTable and single spaces
separating the individual entries in each row. The getDisplayNames
and getFooterText can be used to return appropiately formatted
headers and footers respectively

=head1 AUTHORS

=over

=item *
Damian Smedley

=back

=head1 CONTACT

This module is part of the BioMart project
http://www.ebi.ac.uk/biomart

Questions can be posted to the mart-dev mailing list:
mart-dev@ebi.ac.uk

=head1 METHODS

=cut

package BioMart::Formatter::FASTA;

use strict;
use warnings;

# Extends BioMart::FormatterI
use base qw(BioMart::FormatterI);

sub _new {
    my ($self) = @_;

    $self->SUPER::_new();
}

sub processQuery {
    my ($self, $query) = @_;

    $self->set('original_attributes',[@{$query->getAllAttributes()}]) 
	if ($query->getAllAttributes());
    $self->set('query',$query);
    return $query;
}

sub nextRow {
    my $self = shift;

    my $rtable = $self->get('result_table');
    my $row = $rtable->nextRow;
    if (!$row){
        return;
    }
    my $array_length = @{$row};
    map { $_ ||= ''; } @$row; # get rid of unitialized-value warning message
    my $header_atts = join "|",@{$row}[1..$array_length-1];
    
    #chop $header_atts;
    
    my $seq = ${$row}[0];
    ### SPECIAL LOGIC FOR SNP SEQUENCES, to make them agree with FASTA FORMAT
    ### THE * would suggest the split between two sequnce snp sequences
    ### The allele would go into header, which comes from genomic sequence
    ### in tags separating two snp sequences and that gets replaced by _,
    ### this tag look like %allele%. eg. %A/T%. I am using this assumption
    ### of % sign as TO DATE i have never seen a residue string containing
    ### % sign, 
    ### for those how want to post process them in a different way, may use _
    ### as a splitting point
    if ($seq =~ m/\%(.*)\%/)
    {
		$header_atts .= "|$1";
		## also substiture with *
		$seq =~ s/\%.*\%/\_/;
    }
    
    ########################################################################
    $seq =~ s/(\w{60})/$1\n/g;
    return ">" . $header_atts . "\n"
	       . $seq ."\n";
}

sub getDisplayNames {
    my $self = shift;

    return '';
}

sub isSpecial {
    return 1;
}

1;



