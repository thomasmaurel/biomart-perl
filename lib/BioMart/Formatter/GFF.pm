# $Id$
#
# BioMart module for BioMart::Formatter::GFF
#
# You may distribute this module under the same terms as perl
# itself.

# POD documentation - main docs before the code.

=head1 NAME

BioMart::Formatter::GFF

=head1 SYNOPSIS

The GFF Formatter returns GFF Formatter data for a BioMart query

=head1 DESCRIPTION

The GFF Formatter first of all removes any user chosen attributes from
the BioMart::Query object and adds the appropiate attributes required
for GFF data calculation. These attributes are defined in 'gtf' exportables
for the Dataset being processed. After this initial processing the query is 
run and the ResultTable is processed row by row to calculate the correct
structural data for GFF output

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


package BioMart::Formatter::GFF;

use strict;
use warnings;

# Extends BioMart::FormatterI
use base qw(BioMart::FormatterI);

sub _new {
    my ($self) = @_;

    $self->SUPER::_new();
}

 # overrides the same method from FormatterI
sub processQuery {
    my ($self, $query) = @_;

    $self->set('original_attributes',[@{$query->getAllAttributes()}]) 
	if ($query->getAllAttributes());
    # get exportable for terminal dataset from registry and set (attributes) 
    # on it and remove existing attribute - then set the list - may want a 
    # general method on FormatterI for doing all the rigid ones

    my $final_dataset_order = $query->finalDatasetOrder();
    my $registry = $query->getRegistry();
    
    	# remove all attributes from query
    	$query->removeAllAttributes();
	
    	foreach my $dataset_name(reverse @$final_dataset_order){	
    		my $dataset = $registry->getDatasetByName($query->virtualSchema, $dataset_name);
		if($dataset->visible)
		{		
			if ($dataset->getExportables('gtf', $query->getInterfaceForDataset($dataset_name))){
				$query->setDataset($dataset_name);
				my $attribute_list = $dataset->getExportables('gtf', $query->getInterfaceForDataset($dataset_name));
	    	
	    			my $temp_atts = $attribute_list->getAllAttributes;
	    	
	    			$query->addAttributes($attribute_list->getAllAttributes);
			}
		}
    	}
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
    my $formatted_rows;

    my $attr_tmpl = 'gene_id "%s"; transcript_id "%s"; exon_id "%s"';
    my $exon_tmpl = "%s\tEnsEMBL\texon\t%s\t%s\t.\t%s\t.\t%s";
    my $cds_tmpl = "%s\tEnsEMBL\tCDS\t%s\t%s\t.\t%s\t%s\t%s";
    my $start_tmpl = "%s\tEnsEMBL\tstart_codon\t%s\t%s\t.\t%s\t.\t%s";
    my $stop_tmpl =  "%s\tEnsEMBL\tstop_codon\t%s\t%s\t.\t%s\t.\t%s"; 
	  
    my @lines;

    $row->[3] = ($row->[3] == -1)? '-':'+';
    my $attributes = sprintf($attr_tmpl,$row->[9],$row->[10],$row->[11]);

    push @lines,sprintf($exon_tmpl,$row->[0],$row->[1],
			$row->[2],$row->[3],$attributes);

    if($row->[4]){ # has the exon got a coding region 

	if($row->[7]  && $row->[5]<$row->[4]){
	      
	    my $this_exon_line =  pop(@lines);
	    my $cds_line = pop(@lines);
	    my $exon_line = pop(@lines);

 
	    my $diff = $row->[4]-$row->[5];
	    # if diff = 2 then the final exon has a cds length of 2
	    #           1                                         3
	    #           3                                         1

	    if ($cds_line){
		my @cds = split("\t",$cds_line);
		if($diff == 3){ # CDS must be shortened by 1. 
		    if( $cds[6] eq '+'){
			$cds[4]--;
		    }
		    else {
			$cds[3]++;
		    }    
		}
	    
		if($diff == 2){ # CDS must be shortened by 2.
		    if( $cds[6] eq '+'){
			$cds[4] -= 2;
		    }
		    else {
			$cds[3] += 2;
		    }    
		}

		$cds_line = join("\t",@cds);
	    }
	    
	    $formatted_rows .= $this_exon_line."\n"  if ($this_exon_line);
	    $formatted_rows .= $cds_line."\n" if ($cds_line);
	    $formatted_rows .= $exon_line."\n" if ($exon_line);
	    push @lines,$exon_line;
	    push @lines,$cds_line;
	    push @lines,$this_exon_line;
	}
	
	# if this exon has the stop codon and the CDS length is 3 or less
	# we don't want a CDS line. due to a bug in the production script 
	# the symptom is gtf_cds_chrom_end < gtf_cds_chrom_start
	unless($row->[7]  && $row->[5]<$row->[4]){ 
            # hack to stop the above CDS lines being produced
	    $formatted_rows .= sprintf($exon_tmpl,$row->[0],$row->[1],
				       $row->[2],$row->[3],$attributes)."\n" ;
	    $formatted_rows .= sprintf($cds_tmpl,$row->[0],$row->[4],
				       $row->[5],$row->[3],$row->[8],
				       $attributes)."\n" ;

	    push @lines,sprintf($cds_tmpl,$row->[0],$row->[4],
				$row->[5],$row->[3],$row->[8],$attributes);
	}
    }
    else{
	$formatted_rows .= sprintf($exon_tmpl,$row->[0],$row->[1],
				   $row->[2],$row->[3],$attributes)."\n" ;
    }
	      
    if($row->[6]){ # this is exon with the start codon for this transcript
	$formatted_rows .= sprintf($start_tmpl,$row->[0],$row->[6],
				   $row->[6]+2,$row->[3],$attributes)."\n" ;
	push @lines, sprintf($start_tmpl,$row->[0],$row->[6],
			     $row->[6]+2,$row->[3],$attributes);
    }
    
    if($row->[7]){ # this is exon with the stop codon for this transcript
	$formatted_rows .= sprintf($stop_tmpl,$row->[0],$row->[7],
				   $row->[7]+2,$row->[3],$attributes)."\n" ;
	push @lines,  sprintf($stop_tmpl,$row->[0],$row->[7],
			      $row->[7]+2,$row->[3],$attributes);
    }
    
    return $formatted_rows;
}


sub getDisplayNames {
    my $self = shift;

    return '';# no header required for GFF
}

sub isSpecial {
    return 1;
}


1;



