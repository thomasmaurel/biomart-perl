#!perl -w

# A simple BioMart service CGI script 
# requests: registry, dataset names, dataset configuration and query results

use strict;
use warnings;

#the TAG:lib below gets replaced by OPTIONS{lib}, from user's PERL5LIB
[TAG:lib]

use Config;
use Readonly;

use XML::Simple qw(:strict);
use CGI;
use Cwd;
use POSIX qw(strftime);
use Log::Log4perl;
use File::Basename qw(&basename &dirname);
use BioMart::Web;
use BioMart::Initializer;
use BioMart::Query;
use BioMart::AttributeTable;
use BioMart::QueryRunner;
use BioMart::ResultTable;
use BioMart::Exception;
use Data::Dumper;


use vars qw/ $VERSION $revision $server_host $server_port $log_Dir $cgiLocation $CONF_FILE $LOGGER $WEBQUERY $BIOMART_REGISTRY/;

#the TAG:conf below gets replaced by OPTIONS{conf}, path to registry file
$CONF_FILE = '[TAG:conf]';

#the TAG:server_host below gets replaced by OPTIONS{server_host}
$server_host = '[TAG:server_host]';

#the TAG:server_port below gets replaced by OPTIONS{server_port}
$server_port = '[TAG:server_port]';

#the TAG:log_dir below gets replaced by path to log dir
$log_Dir = '[TAG:log_dir]';

#the TAG:cgiLocation below gets replaced by OPTIONS{cgiLocation}
$cgiLocation = '[TAG:cgiLocation]';

# Initialize master logger for this wrapper script, but only if it's not defined
# already. Other components of system will use the same logger-setup but with 
# different configurations.
if(!defined($LOGGER)) {
    Log::Log4perl->init(dirname($CONF_FILE) . '/log4perl.conf');
    my $script = basename($0);
    $LOGGER = Log::Log4perl->get_logger($script);
    $LOGGER->debug("initialized logger for $script");
}
else {
    $LOGGER->debug("Using existing logger $LOGGER");
}

my $CGI = $ENV{MOD_PERL} ? CGI->new(shift @_) : CGI->new();

my $segment = $CGI->param('segment');
my $url_string = $CGI->self_url();
$url_string =~ m/.*?\/das\/(.*)\/features.*/;
my $dasDSNName = $1;
my @schema__DS = split(/__/, $1);
my $schemaName= $schema__DS[0];
my $dasDatasetName = $schema__DS[1];

#print "MY DAS DATASET: ", $dasDatasetName;
#exit();

my $registry;
if (!$main::BIOMART_REGISTRY)
{
	my $initializer = BioMart::Initializer->new('registryFile'=>$CONF_FILE);
	$registry = $initializer->getRegistry;
} 
else 
{
	$registry = $main::BIOMART_REGISTRY;
}


eval{
	if($segment)
	{	
		if ($segment =~ m/:/) {
			&get_chromosomeAnnotation($segment);
		}
		else {
			if (&featureType($segment) eq 'gene') {
				&get_geneAnnotation($segment);
			}
			else {
				&get_chromosomeAnnotation($segment);
			}
		}
	} 

};
if($@) {
	my $ex = Exception::Class->caught('BioMart::Exception');
	if(!$ex) {
	    $ex = BioMart::Exception->new('non-BioMart die(): '.$@);
	}
	print $ex->error()."\n";
	return;
}

# To decide if its a gene request or a chromosome request when segment=SOMETHING
# where SOMETHING could be chrName or a GeneName
# Algorithm requests all the chromosomes if dasChr exportable exists
# and checks if the requested chromosome exists. If it does, then its a Chromosome request
# otherwise its a gene Request
sub featureType
{
	my $segmentString = shift;
	
	# FIRST check if both dasChr and dasGene exist, if only one exists then this one is being called
	my $geneOk = 0;
	my $chrOk = 0;
	foreach my $schema (@{$registry->getAllVirtualSchemas()}) {
		foreach my $mart (@{$schema->getAllMarts(0)}) {
			foreach my $dataset (@{$mart->getAllDatasets(0)}) {
				if ($dataset->name eq $dasDatasetName) {
					foreach my $exportable (@{$dataset->getExportables()}) {
						if($exportable->type() eq 'dasChr') {
							$chrOk = 1;
						}
						if($exportable->type() eq 'dasGene') {
							$geneOk = 1;
						}
					}
				}
			}
		}
	}
	return 'chromosome' if (!$geneOk && $chrOk);
	return 'gene' if (!$chrOk && $geneOk);
	
	# incase both dasGene and dasChr exist	
	my $temp_results;
	my $dasChrExists = 0;	
	
	my $query = BioMart::Query->new('registry'=>$registry,'virtualSchemaName'=>$schemaName);
     
	$query->setDataset($dasDatasetName);
	
	foreach my $schema (@{$registry->getAllVirtualSchemas()}) {
		foreach my $mart (@{$schema->getAllMarts(0)}) {
			foreach my $dataset (@{$mart->getAllDatasets(0)}) {
				if ($dataset->name eq $dasDatasetName) {
					foreach my $exportable (@{$dataset->getExportables()}) {
						if($exportable->type() eq 'dasChr') {
							foreach my $importable (@{$dataset->getImportables()}) {
								if($importable->type() eq 'dasChr') {
									my @temp_arr = split(/,/, $importable->filterString());
									$query->addAttribute($temp_arr[0]);
									$query->addFilter($temp_arr[0], [$segmentString]);
									$dasChrExists = 1;
								}
							}
						}
					}
				}
			}
		}
	}
	
	return 'gene' if (!$dasChrExists);
	
	open(my $result_buffer, '>', \$temp_results);

	my $query_runner = BioMart::QueryRunner->new();
	$query_runner->uniqueRowsOnly(1);
	$query_runner->execute($query);
	#$query_runner->printHeader();
	$query_runner->printResults($result_buffer);
	#$query_runner->printFooter();		
	close($result_buffer);
	if ($temp_results) {
		return 'chr'; # its a chromosome request
	}
	else {
		return 'gene'; # its a gene request
	}
}



#GeneView

#DAS sources serving non-positional features (or GeneDAS sources) can be attached to GeneView (see
#example for human) which displays gene information. Non-positional feature DAS is a semantic extension 
#to the DAS protocol. It allows exchange of annotations tied to identifiers, such as a HUGO gene name or 
#an Ensembl gene ID, rather than to a segment of reference sequence. Positional data is irrelevant and 
#the annotation applies to the entire entity referenced by the request. GeneDAS annotations are defined 
#as having 'start' and 'end' attributes set to 0 (zero) and the annotation itself is carried in the 
#'note' attribute.

# Ensembl calls this as .../das/DSN/features?segment=ENSGid
sub get_geneAnnotation
{
	my $geneID = shift;
	my $results;
	my $temp_results;
	my @resultRows;
	my $attributeList;
	my $linkURL;
	my $hrefURL;
	my $dsDisplayName; 
	
	my $query = BioMart::Query->new('registry'=>$registry,'virtualSchemaName'=>$schemaName);
     
	$query->setDataset($dasDatasetName);
	
	foreach my $schema (@{$registry->getAllVirtualSchemas()}) {
		foreach my $mart (@{$schema->getAllMarts(0)}) {
			foreach my $dataset (@{$mart->getAllDatasets(0)}) {
				if ($dataset->name eq $dasDatasetName) {
					$dsDisplayName = $dataset->displayName;
					foreach my $exportable (@{$dataset->getExportables()}) {
						if($exportable->type() eq 'dasGene') {
							foreach my $importable (@{$dataset->getImportables()}) {
								if($importable->type() eq 'dasGene') {
									$attributeList = $exportable->attributeString();
									foreach (split(/,/, $exportable->attributeString() ))
									{
										$query->addAttribute($_);	
									}
									# no need to split, this should strictly be a single filter GeneId
									foreach (split(/,/, $importable->filterString() ))
									{
										$query->addFilter($_, [$geneID]);	
									}
								}
							}
						}
					}
				}
			}
		}
	}
	
	# GET THE URL LINK using the second attribute in attributeString, fetch its object and find link URL
	if ($attributeList)
	{
		my @portions = split (/,/,$attributeList);
		my $datasetObj = $registry->getDatasetByName($schemaName, $dasDatasetName);
		my $dataset_conf  = $datasetObj->getConfigurationTree('default');
		my $attributeObj = $dataset_conf->getAttributeByName($portions[1]);
		$linkURL = $attributeObj->link();
		$linkURL =~ s/^exturl\|//;
	}

	open(my $result_buffer, '>', \$temp_results);

	my $query_runner = BioMart::QueryRunner->new();
	$query_runner->uniqueRowsOnly(1);
	$query_runner->execute($query);
	#$query_runner->printHeader();
	$query_runner->printResults($result_buffer);
	#$query_runner->printFooter();		
	close($result_buffer);
	#&dummyResultsGene();
	
	$results .= &header();
	$results .= &GFF_open("http://[TAG:server_host]/[TAG:cgiLocation]/das/$dasDSNName/features");
	$results .= &segment_open($geneID, "1", ""); # first argument should be the same as sent by ensembl as geneID
	
	@resultRows = split(/\n/, $temp_results);
	foreach my $line (@resultRows) {
		my @portions = split (/\t/, $line);
	
		$results .= &feature_open($portions[1], $portions[1]);
		#$results .= &type($portions[1],"no","no","no", $portions[1]);
		$results .= &type($dasDatasetName,"no","no","no", $dsDisplayName);
		#$results .= &method("methodID:unknown", "");
		#$results .= &start("0");
		#$results .= &end("0");
		#$results .= &score("-");
		#$results .= &orientation("0");
		#$results .= &phase("-");
		$results .= &note($portions[2]);

		$hrefURL = sprintf ($linkURL, defined ($linkURL) ? $portions[1] : '');
		$results .= &link($hrefURL, $portions[1])  if($hrefURL);

		$results .= &feature_close();
	}	
	
	$results .= &segment_close();
	$results .= &GFF_close();
	$results .= &footer();
	
	&printDASHttpHeader(1); # 1 for DAS success code 200		
	print $results;
}


#ContigView and CytoView

#A genomic DAS source serves data in the format specified in the DAS/1.5 specification. In Ensembl, 
#genomic DAS sources can be attached to ContigView and CytoView (see examples in human) if the annotation 
#is in chromosomal coordinates, on contigs or on any basic assembly structure known to Ensembl for that 
#species. For genomic DAS sources the assembly version is important as otherwise features from a source 
#annotation (e.g. NCBI 34 human assembly) may be offset in ContigView.

#Please note that for most species, Ensembl chromosomes are named like "1", "2", "X", "Y" rather than 
#like "chr1", "chr2", "chrX", "chrY". The exceptions are the Drosophila melanogaster, Anopheles gambiae, 
#Caenorhabditis elegans, and Saccharomyces cerevisiae genomes which uses other naming conventions.

# Ensembl calls this as .../das/DSN/features?segment=13:31787617,31871805

sub get_chromosomeAnnotation
{
	my $coordinates_string = shift;
	my $resultsHash;
	my $results;
	my $temp_results;
	my @resultRows;
	my $counter = 0;
	my ($chromosome, $start, $end);
	
	if ($coordinates_string =~ m/:/) {
		my @portions = split( /:/, $coordinates_string);
		$chromosome =  $portions[0];
		($start , $end ) = split (/\,/, $portions[1]) ;
	}
	else {
		$chromosome = $coordinates_string;
	}
	
	my $query = BioMart::Query->new('registry'=>$registry,'virtualSchemaName'=>$schemaName);
     
	$query->setDataset($dasDatasetName);

	foreach my $schema (@{$registry->getAllVirtualSchemas()}) {
		foreach my $mart (@{$schema->getAllMarts(0)}) {
			foreach my $dataset (@{$mart->getAllDatasets(0)}) {
				if ($dataset->name eq $dasDatasetName) {
					foreach my $exportable (@{$dataset->getExportables()}) {
						if($exportable->type() eq 'dasChr') {
							foreach my $importable (@{$dataset->getImportables()}) {
								if($importable->type() eq 'dasChr') {
									foreach (split(/,/, $exportable->attributeString() ))
									{
										$query->addAttribute($_);	
									}							
									my @temp_arr = split(/,/, $importable->filterString());
									$query->addFilter($temp_arr[0], [$chromosome]);
									$query->addFilter($temp_arr[1], [$start])		if ($start);
									$query->addFilter($temp_arr[2], [$end])		if ($end);									
								}
							}
						}
					}
				}
			}
		}
	}

	open(my $result_buffer, '>', \$temp_results);

	my $query_runner = BioMart::QueryRunner->new();
	$query_runner->uniqueRowsOnly(1);
	$query_runner->execute($query);
	#$query_runner->printHeader();
	$query_runner->printResults($result_buffer);
	#$query_runner->printFooter();		
	close($result_buffer);


	# establish a multi-dimensional hash to store all the structure table information for xml transformation
	@resultRows = split(/\n/, $temp_results);
	foreach my $line (@resultRows) {
		no warnings 'uninitialized';
		my @portions = split (/\t/, $line);
		
		# for every transcript reinitialise the counter assuming the translation_id 'portion[8]' 
		# changes with every new transcript. reason we append counter with translation Id is to make it
		# unique just like there is a unique exon_stable_id
		if (! $resultsHash->{$portions[0]}->{'transcript'}->{$portions[1]}) {
			$counter = 0;
		}
		
		$resultsHash->{$portions[0]}->{'transcript'}->{$portions[1]}->{'start'} = $portions[2];
		$resultsHash->{$portions[0]}->{'transcript'}->{$portions[1]}->{'end'} = $portions[3];
		$resultsHash->{$portions[0]}->{'transcript'}->{$portions[1]}->{'strand'} = $portions[4];

		$resultsHash->{$portions[0]}->{'transcript'}->{$portions[1]}->{'exon'}->{$portions[5]}->{'start'} = $portions[6];
		$resultsHash->{$portions[0]}->{'transcript'}->{$portions[1]}->{'exon'}->{$portions[5]}->{'end'} = $portions[7];

		$resultsHash->{$portions[0]}->{'transcript'}->{$portions[1]}->{'exon'}->{$portions[5]}->
					{'translation'}->{$portions[8]."-".$counter}->{'start'} = $portions[9];
				
		$resultsHash->{$portions[0]}->{'transcript'}->{$portions[1]}->{'exon'}->{$portions[5]}->
					{'translation'}->{$portions[8]."-".$counter}->{'end'} = $portions[10];

		$resultsHash->{$portions[0]}->{'transcript'}->{$portions[1]}->{'exon'}->{$portions[5]}->
					{'translation'}->{$portions[8]."-".$counter}->{'translationGroupId'} = $portions[8];

		$counter++;

	}
	
	#print Dumper($resultsHash);	
	
	####  represent $resultsHash in terms of DAS XML
		
	$results .= &header();
	$results .= &GFF_open("http://[TAG:server_host]/[TAG:cgiLocation]/das/$dasDSNName/features");	
	$results .= &segment_open($chromosome, $start, $end);

	################################### ADDING TRANSCRIPT FEATURES
	foreach my $geneID (keys %{$resultsHash}) {
		foreach my $transcriptID (keys %{$resultsHash->{$geneID}->{'transcript'}}) {
		
			$results .= &feature_open($transcriptID, $transcriptID);
			$results .= &type("transcript","no","no","no", "transcript");
			$results .= &method("methodID:unknown", "");
			$results .= &start($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}->{'start'});
			$results .= &end($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}->{'end'});
			$results .= &score("-");
			
			$results .= &orientation("+") 
				if ($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}->{'strand'} == 1) ;
			$results .= &orientation("-") 
				if ($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}->{'strand'} == -1) ;
			
			$results .= &phase("-");
			$results .= &feature_close();
		}
	}
	################################### ADDING EXON FEATURES

	foreach my $geneID (keys %{$resultsHash}) {
		foreach my $transcriptID (keys %{$resultsHash->{$geneID}->{'transcript'}}) {
			foreach my $exonID (keys %{$resultsHash->{$geneID}->{'transcript'}
							->{$transcriptID}->{'exon'}}) {
							
				$results .= &feature_open($exonID, $exonID);
				$results .= &type("exon","no","no","no", "exon");
				$results .= &method("methodID:unknown", "");
				$results .= &start($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}
											->{'exon'}->{$exonID}->{'start'});
				$results .= &end($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}
											->{'exon'}->{$exonID}->{'end'});
				$results .= &score("-");
			
				$results .= &orientation("+") 
					if ($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}->{'strand'} == 1) ;
				$results .= &orientation("-") 
					if ($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}->{'strand'} == -1) ;
		
				$results .= &phase("-");
			
				$results .= &group($transcriptID, "transcript", $transcriptID) ;
				$results .= &group($geneID, "gene", $geneID) ;
				$results .= &feature_close();
			}
		}
	}
	
	
	################################### ADDING TRANSLATION FEATURES
	
	foreach my $geneID (keys %{$resultsHash}) {
		foreach my $transcriptID (keys %{$resultsHash->{$geneID}->{'transcript'}}) {
			foreach my $exonID (keys %{$resultsHash->{$geneID}->{'transcript'}
							->{$transcriptID}->{'exon'}}) {
				foreach my $translationID (keys %{$resultsHash->{$geneID}->{'transcript'}
							->{$transcriptID}->{'exon'}->{$exonID}->{'translation'} }) {
				
					$results .= &feature_open($translationID, $translationID);
					$results .= &type("translation","no","no","no", "translation");
					$results .= &method("methodID:unknown", "");
					$results .= &start($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}
								->{'exon'}->{$exonID}->{'translation'}->{$translationID}->{'start'});
					$results .= &end($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}
								->{'exon'}->{$exonID}->{'translation'}->{$translationID}->{'end'});
					$results .= &score("-");
				
					$results .= &orientation("+") 
						if ($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}->{'strand'} == 1) ;
					$results .= &orientation("-") 
						if ($resultsHash->{$geneID}->{'transcript'}->{$transcriptID}->{'strand'} == -1) ;

					$results .= &phase("-");
			
					my $tGID =  $resultsHash->{$geneID}->{'transcript'}
									->{$transcriptID}->{'exon'}->{$exonID}->{'translation'}
									->{$translationID}->{'translationGroupId'};
					$results .= &group($tGID, "translation", $tGID ) ;
					$results .= &group($transcriptID, "transcript", $transcriptID) ;

					$results .= &feature_close();
				}
			}
		}
	}
	
	
	###############################################################
	$results .= &segment_close();
	$results .= &GFF_close();
	$results .= &footer();
	
	&printDASHttpHeader(1); # 1 for DAS success code 200	
	print $results;
				
	#&dummyResultsContig();

}

########################################### DAS HTTP HEADER
sub printDASHttpHeader
{
	my $val = shift;
	print $CGI->header(	-'type' =>'text/xml',
								-'X-DAS-Version' => 'DAS/1.5',
								-'X-DAS-Status'  => '200',
								-'X-DAS-Capabilities' => 'dsn/1.0; features/1.0;');
	
}


########################################### FORMATTING SUBROUTINES
sub header
{
	my $version;
	
	return qq|<?xml version="1.0" standalone="yes"?>
	<!DOCTYPE DASGFF SYSTEM "http://www.biodas.org/dtd/dasgff.dtd">
	<DASGFF>	|;
}

sub GFF_open
{
	my $hrefURL = shift;
	return qq|
	<GFF version="1.0" href="|.$hrefURL.qq|" >		|;
}
sub segment_open
{
	my ($id, $start, $end) = @_;
	return qq|
	<SEGMENT id="|.$id.qq|" version="1.0" start="|.$start.qq|" stop="|.$end.qq|">	|;
}

sub feature_open
{
	my ($id, $label) = @_;
	return qq|
		<FEATURE id="|.$id.qq|" label="|.$label.qq|">	|;
}
sub type
{
	my ($id, $reference, $subparts, $superparts, $val) = @_;
	# return qq|
	#	<TYPE id="|.$id.qq|"  reference="|.$reference.qq|" subparts="|.$subparts.qq|" superparts="|.$superparts.qq|">$val</TYPE>	|;
	return qq|
		<TYPE id="|.$id.qq|">$val</TYPE>	|;

}
sub method
{
	my ($id, $val) = @_;
	return qq|
		<METHOD id="|.$id.qq|">$val</METHOD>	|;
	

}
sub start
{
	my $val = shift;	
	return qq|
		<START>$val</START>	|;
}
sub end
{
	my $val = shift;	
	return qq|
		<END>$val</END>	|;

}
sub score
{
	my $val = shift;	
	return qq|
		<SCORE>$val</SCORE>	|;

}
sub orientation
{

	my $val = shift;	
	return qq|
		<ORIENTATION>$val</ORIENTATION>	|;
}
sub phase
{
	my $val = shift;	
	return qq|
		<PHASE>$val</PHASE>	|;

}
sub note
{
	my $val = shift;	
	return qq|
		<NOTE>$val</NOTE>	|;
}
sub link
{
	my ($url, $label) = @_;
	return qq|
		<LINK href="|.$url.qq|">$label</LINK>|;
}
sub target
{

}
sub group
{
	my ($id, $type, $label) = @_;
	return qq|
		<GROUP id="|.$id.qq|" type="|.$type.qq|" label="|.$label.qq|"/>	|;
}
sub feature_close
{
	return qq|
	</FEATURE>	|;
}
sub segment_close
{
	return qq|
    </SEGMENT>    |;

}
sub GFF_close
{
	return qq|
	</GFF>	|;
}
sub footer
{
	return qq|
	</DASGFF>	|;
}

##################################################################
##################################################################
sub dummyResultsGene
{
	print qq|
<?xml version="1.0" standalone="yes"?>
<!DOCTYPE DASGFF SYSTEM "http://www.biodas.org/dtd/dasgff.dtd">
<DASGFF>
 <GFF version="1.0" href="http://test.biomart.org/biomart/das/BioMart_ENS_HUMAN/features">
    <SEGMENT id="ENSG00000138411" version="1.0" start="1" stop="">
    <FEATURE id="01self_01" label="01self_01">
      <TYPE id="01hsap"  reference="no" subparts="no" superparts="no">01hsap</TYPE>
      <METHOD id="01hsap">01hsap</METHOD>
      <START>0</START>
      <END>0</END>
      <ORIENTATION>0</ORIENTATION>
      <NOTE>my own gene DESCRIPTION - cheers</NOTE>
    </FEATURE>
    </SEGMENT>
  </GFF>
</DASGFF>
	|;
}
sub dummyResultsContig()
{
print qq|
<?xml version='1.0' standalone='no' ?>
<!DOCTYPE DASGFF SYSTEM 'dasgff.dtd' >
<DASGFF>
  <GFF version="1.0" href="http://test.biomart.org/biomart/das/BioMart_ENS_HUMAN/features?segment=13:31787617,31871805">
    <SEGMENT id="13" version="28_35a" start="31787617" stop="31871805">
      
      <FEATURE id="ENST00000267071" label="BRCA2">
        <TYPE id="transcript">transcript</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31787617</START>

        <END>31871805</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
      </FEATURE>
      <FEATURE id="ENSE00000939175" label="ENSE00000939175">
        <TYPE id="exon">exon</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31829879</START>
        <END>31830066</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939160" label="ENSE00000939160">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31791214</START>

        <END>31791462</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>

      <FEATURE id="ENSE00000939159" label="ENSE00000939159">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31788559</START>
        <END>31788664</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00001184784" label="ENSE00001184784">
        <TYPE id="exon">exon</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31787617</START>
        <END>31787804</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939174" label="ENSE00000939174">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31828565</START>

        <END>31828746</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>

      <FEATURE id="ENSE00000939173" label="ENSE00000939173">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31826998</START>
        <END>31827425</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939171" label="ENSE00000939171">
        <TYPE id="exon">exon</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31818964</START>
        <END>31819033</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939169" label="ENSE00000939169">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31816695</START>

        <END>31816790</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>

      <FEATURE id="ENSE00000939168" label="ENSE00000939168">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31808402</START>
        <END>31813333</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939167" label="ENSE00000939167">
        <TYPE id="exon">exon</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31804409</START>
        <END>31805524</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939180" label="ENSE00000939180">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31843093</START>

        <END>31843237</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>

      <FEATURE id="ENSE00000939166" label="ENSE00000939166">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31803056</START>
        <END>31803167</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939165" label="ENSE00000939165">
        <TYPE id="exon">exon</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31801580</START>
        <END>31801629</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939164" label="ENSE00000939164">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31798636</START>

        <END>31798750</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>

      <FEATURE id="ENSE00001351327" label="ENSE00001351327">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31871746</START>
        <END>31871805</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00001184789" label="ENSE00001184789">
        <TYPE id="exon">exon</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31870299</START>
        <END>31871347</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939178" label="ENSE00000939178">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31842539</START>

        <END>31842694</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>

      <FEATURE id="ENSE00000939163" label="ENSE00000939163">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31798379</START>
        <END>31798419</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939192" label="ENSE00000939192">
        <TYPE id="exon">exon</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31869035</START>
        <END>31869181</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939177" label="ENSE00000939177">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31835316</START>

        <END>31835670</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>

      <FEATURE id="ENSE00001394102" label="ENSE00001394102">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31834660</START>
        <END>31834830</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939162" label="ENSE00000939162">
        <TYPE id="exon">exon</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31798238</START>
        <END>31798287</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939189" label="ENSE00000939189">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31866826</START>

        <END>31867070</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>

      <FEATURE id="ENSE00000939187" label="ENSE00000939187">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31852144</START>
        <END>31852282</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939185" label="ENSE00000939185">
        <TYPE id="exon">exon</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31851887</START>
        <END>31852050</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939183" label="ENSE00000939183">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31851454</START>

        <END>31851652</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>

      <FEATURE id="ENSE00000939181" label="ENSE00000939181">
        <TYPE id="exon">exon</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31848807</START>
        <END>31848928</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSE00000939161" label="ENSE00000939161">
        <TYPE id="exon">exon</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31797213</START>
        <END>31797321</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
        <GROUP id="ENSG00000139618" type="gene" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-1" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31788598</START>

        <END>31788664</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>

      <FEATURE id="ENSP00000267071-2" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31791214</START>
        <END>31791462</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-3" label="BRCA2">
        <TYPE id="translation">translation</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31797213</START>
        <END>31797321</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-4" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31798238</START>

        <END>31798287</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>

      <FEATURE id="ENSP00000267071-5" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31798379</START>
        <END>31798419</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-6" label="BRCA2">
        <TYPE id="translation">translation</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31798636</START>
        <END>31798750</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-7" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31801580</START>

        <END>31801629</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>

      <FEATURE id="ENSP00000267071-8" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31803056</START>
        <END>31803167</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-9" label="BRCA2">
        <TYPE id="translation">translation</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31804409</START>
        <END>31805524</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-10" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31808402</START>

        <END>31813333</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>

      <FEATURE id="ENSP00000267071-11" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31816695</START>
        <END>31816790</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-12" label="BRCA2">
        <TYPE id="translation">translation</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31818964</START>
        <END>31819033</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-13" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31826998</START>

        <END>31827425</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>

      <FEATURE id="ENSP00000267071-14" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31828565</START>
        <END>31828746</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-15" label="BRCA2">
        <TYPE id="translation">translation</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31829879</START>
        <END>31830066</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-16" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31834660</START>

        <END>31834830</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>

      <FEATURE id="ENSP00000267071-17" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31835316</START>
        <END>31835670</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-18" label="BRCA2">
        <TYPE id="translation">translation</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31842539</START>
        <END>31842694</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-19" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31843093</START>

        <END>31843237</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>

      <FEATURE id="ENSP00000267071-20" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31848807</START>
        <END>31848928</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-21" label="BRCA2">
        <TYPE id="translation">translation</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31851454</START>
        <END>31851652</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-22" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31851887</START>

        <END>31852050</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>

      <FEATURE id="ENSP00000267071-23" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31852144</START>
        <END>31852282</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-24" label="BRCA2">
        <TYPE id="translation">translation</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31866826</START>
        <END>31867070</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>

        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="ENSP00000267071-25" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31869035</START>

        <END>31869181</END>
        <SCORE>-</SCORE>
        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>

      <FEATURE id="ENSP00000267071-26" label="BRCA2">
        <TYPE id="translation">translation</TYPE>
        <METHOD id="ensembl">ensembl</METHOD>
        <START>31870299</START>
        <END>31870907</END>
        <SCORE>-</SCORE>

        <ORIENTATION>+</ORIENTATION>
        <PHASE>-</PHASE>
        <GROUP id="ENSP00000267071" type="translation" label="BRCA2" />
        <GROUP id="ENST00000267071" type="transcript" label="BRCA2" />
      </FEATURE>
      <FEATURE id="13/q13.1" label="gpos50">
        <TYPE id="karyotype">karyotype</TYPE>

        <METHOD id="ensembl">ensembl</METHOD>
        <START>31100001</START>
        <END>32900000</END>
        <SCORE>-</SCORE>
        <ORIENTATION>0</ORIENTATION>
        <PHASE>-</PHASE>

      </FEATURE>
    </SEGMENT>
  </GFF>
</DASGFF>

|;
}
