#
# BioMart module for BioMart::Formatter::XLS
#
# You may distribute this module under the same terms as perl
# itself.

# POD documentation - main docs before the code.

=head1 NAME

BioMart::Formatter::XLS

=head1 SYNOPSIS

The XLS Formatter returns XLS format data
for a BioMart query's ResultTable

=head1 DESCRIPTION

When given a BioMart::ResultTable containing the results of 
a BioMart::Query the XLS Formatter will return XLS file, open 
in the browser if it supports xls mime type.


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

package BioMart::Formatter::XLS;

use strict;
use warnings;
use Readonly;
use Spreadsheet::WriteExcel;
use Spreadsheet::WriteExcel::Big;

# Extends BioMart::FormatterI
use base qw(BioMart::FormatterI);

sub _new {
    my ($self) = @_;
    $self->SUPER::_new();
    
}

sub getXlsString
{
    my $self = shift;
    return $self->get('xlsString');
}

sub processQuery {
    my ($self, $query) = @_;
    $self->set('original_attributes',[@{$query->getAllAttributes()}]) 
	if ($query->getAllAttributes());
    $query = $self->setHTMLAttributes($query);
    $self->set('query',$query);
    return $query;
}

sub printResults {
    	my ($self, $filehandle, $lines) = @_;
	
	# on web26 the filehandle was getting lost/corrupted so best to create from scratch - not necessary if using just WriteExcel for some reason. HOWEVER this fix broke all other setups so revert - to be investigated in the future if it appears anywhere else
	# $filehandle = IO::File->new();
	# my $tie = ref tied( *STDOUT );# always 'Apache' even for gz on web26 - hence don't get zipped output
	# tie *$filehandle, $tie; 
	# binmode($filehandle); 


	my $workbook  = Spreadsheet::WriteExcel::Big->new($filehandle);  
	          	
      #---------------------------------------- worksheet properties
    	#binmode(STDOUT);
    	#my $workbook = Spreadsheet::WriteExcel::Big->new("/homes/syed/Desktop/temp9/biomart-web/lib/BioMart/Formatter/perl.xls");
	#my $workbook = Spreadsheet::WriteExcel::Big->new(\*STDOUT);
	#tie *XLS => $r;  # Tie to the Apache::RequestRec object
    	#binmode(*XLS);
    	#my $workbook = Spreadsheet::WriteExcel::Big->new(\*XLS);
	
	# Add a worksheet
	my $worksheet = $workbook->add_worksheet();
	$self->attr('workbook', $workbook);
	$self->attr('worksheet', $worksheet);
	$self->attr('rows', 0);
	$self->attr('columns', 0);
	my $format = $self->get('workbook')->addformat();
	$format->set_align('left');
	$format->set_bg_color('white');
    	$format->set_color('black');    
	$self->attr('format', $format);
	$self->attr('colWidth', undef);
	#-------------------------------------------------------------	

	my @displayNames = $self->getTextDisplayNames();

    # Enclose non-numeric values in double quotes & escape the quotes already in them
    #open (STDME, ">>/homes/syed/Desktop/temp4/biomart-web/lib/BioMart/Formatter/hiya.txt");
    #print STDME "\n====================================================\n";
    
    my $formatDisplay = $self->get('workbook')->addformat();
    $formatDisplay->set_bold();
    $formatDisplay->set_align('centre'); 
    $formatDisplay->set_bg_color('black');
    $formatDisplay->set_color('white');    
    my $width;
    foreach(@displayNames) {
		#print STDME $_, "\t ***** ", length($_), " ^^^\tLINES: ", $lines;
		
		$width->{$self->get('columns')} = length($_) * 1.2 ;
		#print STDME $width->{$self->get('columns')}, " *******\t";
		$self->get('worksheet')->set_column($self->get('columns'), $self->get('columns'), $width->{$self->get('columns')});
		$self->get('worksheet')->write($self->get('rows'), $self->get('columns'), $_, $formatDisplay);
		$self->set('columns', $self->get('columns') + 1);
    }
	$self->set('rows', $self->get('rows') + 1);
	$self->get('worksheet')->freeze_panes(1, 0); # Freeze the first row
	$self->set('colWidth', $width);
	
	#print STDME "\n====================================================\n";
	#close(STDME);

	#------------------------------------------------------------------------------------
		
	my $new_row;
	my $new_row_contents;       
	my $rtable = $self->get('result_table');
	my $counter = 0;
	my $row;	
	
	while ($rtable->hasMoreRows)
	{
		$self->set('columns',0);
		$new_row = ();
		$counter++;
		$row = $rtable->nextRow;
		if (!$row || ($lines && $counter > $lines))
		{
		 	$self->closeWorkBook;
		 	#open    TMP, ">/homes/syed/Desktop/temp4/biomart-web/lib/BioMart/Formatter/fh_007.xls" or die "Couldn't open file: $!";
			#binmode TMP;
			#print   TMP  $xls_str;
			#close   TMP;
			return;    	
   		}

		map { $_ ||= q{}; } @$row;
   		my $attribute_positions = $self->get('attribute_positions');
	   	my $attribute_url_positions = $self->get('attribute_url_positions');
   		my $attribute_url = $self->get('attribute_url');

	   	#my $dataset1_end = $self->get('dataset1_end');

   		for (my $i = 0; $i < @{$attribute_positions}; $i++)
	   	{
     		if ($$attribute_url[$i])
     		{
     	  		my @url_data = map {$$row[$_]} @{$$attribute_url_positions[$i]};
		   		my $url_string = sprintf($$attribute_url[$i],@url_data);
		   		#push @{$new_row}, $url_string, $$row[$$attribute_positions[$i]];
	   			$new_row_contents->{value} = $$row[$$attribute_positions[$i]];
	   			$new_row_contents->{URL} = $url_string;	   		   		
	       	}
     	  	else
       		{
	  			$new_row_contents->{value} = $$row[$$attribute_positions[$i]];
		   		$new_row_contents->{URL} = undef;	   		   		
     	  	}
   			push @{$new_row}, $new_row_contents; 
	   		$new_row_contents = ();      	

   		}	
	
		#------------------------------------------------------------------------------
		# Enclose non-numeric values in double quotes & escape the quotes already in them
		#open (STDME, ">>/homes/syed/Desktop/temp4/biomart-web/lib/BioMart/Formatter/hiya.txt");
    		foreach(@{$new_row}) 
    		{
			if($self->get('colWidth')->{$self->get('columns')} < length($_->{value}) )
			{
				if ( length($_->{value}) > 200)
				{
					$self->get('colWidth')->{$self->get('columns')} = 200; # maximum column display length
					$self->get('worksheet')->set_column($self->get('columns'), $self->get('columns'), 200);
				}
				else
				{
					$self->get('colWidth')->{$self->get('columns')} = length($_->{value}); 
					$self->get('worksheet')->set_column($self->get('columns'), $self->get('columns'), length($_->{value}));					
				}
			}
			if($_->{URL})
			{
				#print STDME $_->{value}," : ", $_->{URL} ,"\t\n";
				## tab below with $_->{value} is prepended to handle hyperlinks on numeric values.
				$self->get('worksheet')->write_url($self->get('rows'), $self->get('columns'), $_->{URL}, $_->{value} ); # , $self->get('format'));
			}
			else
			{
				#print STDME $_->{value}, "\t\n";
				$self->get('worksheet')->write($self->get('rows'), $self->get('columns'), $_->{value} ); # , $self->get('format'));
			}
			$self->set('columns', $self->get('columns') + 1);
    		}
	    	#print STDME "\n\n\n";
		#close(STDME);    
		#------------------------------------------------------------------------------	
		$self->set('rows', $self->get('rows') + 1);
	}

	$self->closeWorkBook;	

		#open    TMP, ">/homes/syed/Desktop/temp4/biomart-web/lib/BioMart/Formatter/fh_007.xls" or die "Couldn't open file: $!";
		#binmode TMP;
		#print   TMP  $xls_str;
		#close   TMP;
		
	return;

	# Create the final record-string
	#   	return $row;
	#return "\nHey, u stay quiet, I will manage that myself - u understand me or do we have a communication barrier!!";
	
}

sub getDisplayNames {
	return undef;
}


sub closeWorkBook
{
	my $self = shift;
	$self->get('workbook')->close;
}

sub getFileType {
    return 'xls';
}

sub getMimeType {
    return 'application/vnd.ms-excel';
}

sub isBinary {
    return 1;
}

1;



