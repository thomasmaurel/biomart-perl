#
# BioMart module for BioMart::Formatter::AXTPLUS
#
# You may distribute this module under the same terms as perl
# itself.

# POD documentation - main docs before the code.

=head1 NAME

BioMart::Formatter::AXTPLUS

=head1 SYNOPSIS

TODO: Synopsis here.

=head1 DESCRIPTION

  AXTPLUS Formatter
  This is an extension of the axt format, with an extended header 
  and the freedom to have the qy_sequence in - strand (axt assumes 
  always qy_sequence to be i + strand)
  
=head1 EXAMPLE
    
  Like the axt format, there are 4 lines per axtplus alignment:

  header
  sp1_sequence
  sp2_sequence
  newline

  The header is now 12 spaced-separated columns (only 9 in the former axt format)
 
  index sp1_seqname sp1_start sp1_end sp1_strand sp2_seqname sp2_start sp2_end sp2_strand \
  score sp1_length sp2_length

  An example:

  0 X 103128639 103128710 - scaffold_145 53965 54036 - 39 153692391 307110
  ggctgcaaggtggagtccgtccacctgaatgtggaggccgtgaacacacaccgggagaagcctgaggtaggt
  ggctgtaaggtggagtcaatcagcctgaacgtggaagcggtcaacacgcacagagagagaccggaggtgggt

  
=head1 AUTHORS

=over

=item *
benoit@ebi.ac.uk

=back

=head1 CONTACT

This module is part of the BioMart project
http://www.ebi.ac.uk/biomart

Questions can be posted to the mart-dev mailing list:
mart-dev@ebi.ac.uk

=head1 METHODS

=cut

package BioMart::Formatter::AXTPLUS;

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
    $self->set('original_attributes',[@{$query->getAllAttributes()}]) if ($query->getAllAttributes());
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
    # on a line you have spe1(8entries), spe2(7entries), speN(7entries),and so on... 
    #
    #spe1_raw_sequence Name  Dnafrag start  Dnafrag end  Dnafrag strand  Length  Cigar line Score 
    #spe2_raw_sequence Name  Dnafrag start  Dnafrag end  Dnafrag strand  Length  Cigar line
    
    #my $lenght =  @{$row}; # get size f array
    #return ("$lenght\n");

       my $seq1    = $row->[0] ;
    my $chr1    = $row->[1] ;
    my $start1  = $row->[2] ;
    my $end1    = $row->[3] ;
    my $strand1 = $row->[4] ;
    #my $score1  = $row->[5] ;
    my $length1 = $row->[5] ;
    my $cigar1  = $row->[6] ;
    my $score1  = $row->[7] ;
    
    my $seq2    = $row->[8] ;
    my $chr2    = $row->[9] ;
    my $start2  = $row->[10] ;
    my $end2    = $row->[11] ;
    my $strand2 = $row->[12] ;
    my $length2 = $row->[13] ;
    my $cigar2  = $row->[14] ;
    my $aln_nb = 0 ;
    
    
    my ($hstart1, $hend1, $hstrand1, $hstart2, $hend2, $hstrand2);
    if ($strand1 < 0 ){
	$hstrand1 = "-";
	$hstart1  = $length1 - $end1 + 1;
	$hend1    =  $length1 - $start1 + 1;
    } else {
	$hstrand1 = "+";
	$hstart1  = $start1;
	$hend1    =  $end1;
    }	
    
    if ($strand2 < 0 ){
	$hstrand2 = "-";
	$hstart2  = $length2 - $end2 + 1;
	$hend2    =  $length2 - $start2 + 1;
    } else {
	$hstrand2 = "+";
	$hstart2  = $start2;
	$hend2    =  $end2;
    }
	
    my $line1 =   sprintf("%d %5s %10d %10d %-1s %5s %10d %10d %-1s %s %10d %10d", $aln_nb,$chr1,$hstart1,$hend1,$hstrand1,$chr2,$hstart2,$hend2,$hstrand2,$score1,$length1,$length2);
    my $line2 =   sprintf( _get_aligned_sequence_from_original_sequence_and_cigar_line($seq1, $cigar1));
    my $line3 =   sprintf( _get_aligned_sequence_from_original_sequence_and_cigar_line($seq2, $cigar2));
    return ("$line1\n$line2\n$line3\n\n");
    
    $aln_nb++;
    
}

sub getDisplayNames {
    my $self = shift;
    return $self->getTextDisplayNames("\t");
}

# subroutines from AXT.pm <alpha version>
#--------------------------------------------
sub _get_aligned_sequence_from_original_sequence_and_cigar_line  {
    
    my ($original_sequence, $cigar_line) = @_;
    my $aligned_sequence = "";

    return undef if (!$original_sequence or !$cigar_line);
    
    my $seq_pos = 0;
    
    my @cig = ( $cigar_line =~ /(\d*[GMD])/g );
    for my $cigElem ( @cig ) {
	
	my $cigType = substr( $cigElem, -1, 1 );
	my $cigCount = substr( $cigElem, 0 ,-1 );
	$cigCount = 1 unless ($cigCount =~ /^\d+$/);
	#print "-- $cigElem $cigCount $cigType\n";
	if( $cigType eq "M" ) {
	    $aligned_sequence .= substr($original_sequence, $seq_pos, $cigCount);
	    $seq_pos += $cigCount;
	} elsif( $cigType eq "G" or $cigType eq "D") {
	    
	    $aligned_sequence .=  "-" x $cigCount;
	    
	}
    }
    warn ("Cigar line ($seq_pos) does not match sequence lenght (".length($original_sequence).")") if ($seq_pos != length($original_sequence));
    
    return $aligned_sequence;

}
#--------------------------------------------
sub _rc{
    my ($seq) = @_;

    $seq = reverse($seq);
    $seq =~ tr/YABCDGHKMRSTUVyabcdghkmrstuv/RTVGHCDMKYSAABrtvghcdmkysaab/;

    return $seq;
}
#--------------------------------------------
sub _rcCigarLine{
    my ($cigar_line) = @_;
        
    #print STDERR "###cigar_line $cigar_line\n";
    my @cig = ( $cigar_line =~ /(\d*[GMD])/g );
    my @rev_cigar = reverse(@cig);
    my $rev_cigar;
    for my $cigElem ( @rev_cigar ) { 
	  $rev_cigar.=$cigElem;
    }			 
    #print STDERR "###rev_cigar $rev_cigar\n";
    return $rev_cigar;
    
}
#--------------------------------------------


sub isSpecial {
    return 1;
}
1;



