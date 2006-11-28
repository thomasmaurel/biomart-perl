#!perl -w

# $Id$

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


use vars qw/ $VERSION $revision $server_host $server_port $log_Dir $cgiLocation $CONF_FILE $LOGGER $WEBQUERY $BIOMART_REGISTRY/;

#the TAG:conf below gets replaced by OPTIONS{conf}, path to registry file
[TAG:conf]

#the TAG:server_host below gets replaced by OPTIONS{server_host}
[TAG:server_host]

#the TAG:server_port below gets replaced by OPTIONS{server_port}
[TAG:server_port]

#the TAG:log_dir below gets replaced by path to log dir
[TAG:log_dir]

#the TAG:cgiLocation below gets replaced by OPTIONS{cgiLocation}
[TAG:cgiLocation]

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

#my $CGI       = CGI->new();
my $type          = $CGI->param('type');
my $vschema_name  = $CGI->param('virtualschema');# || 'default'; 
my $dataset_name  = $CGI->param('dataset');
my $version       = $CGI->param('version');
my $atts          = $CGI->param('attribute');
my $fils          = $CGI->param('filter');
my $mart_name     = $CGI->param('mart');
my $martuser      = $CGI->param('martuser') || 'default';
my $interface     = $CGI->param('interface') || 'default';

my $path = "/".$cgiLocation."/martservice";



my $registry;
if (!$main::BIOMART_REGISTRY){
my $initializer = BioMart::Initializer->new('registryFile'=>$CONF_FILE);
$registry = $initializer->getRegistry;
} else {
$registry = $main::BIOMART_REGISTRY;
}





eval{
	if($type)
	{	
    		if ($type eq "registry") {
			&get_registry($registry,$server_host,$server_port,$path);
		}	  
		elsif ($type eq "datasets") {
			&get_datasets($registry,$vschema_name,$mart_name,$martuser);
		}  
		elsif ($type eq "interfaces"){
			&get_interfaces($registry,$vschema_name,$mart_name,$martuser,$dataset_name);
		}
		elsif ($type eq "configuration") {
			&get_configuration($registry,$vschema_name,$dataset_name,$interface,$martuser);
		} 
		elsif ($type eq "filters") {
			&get_filters($registry,$vschema_name,$dataset_name,$interface,$martuser);
		}
		elsif ($type eq "attributes") {
			&get_attributes($registry,$vschema_name,$dataset_name,$interface,$martuser);
		}
		elsif ($type eq "versioncheck") {	
			&version_check($registry,$vschema_name,$mart_name,$version);
		} 
		elsif ($type eq "version") {
			&version($registry,$vschema_name,$mart_name);
		}
	} 
    	else{
		my $xml = $CGI->param('query');
		my $ip = $CGI->remote_host();
		&createLog($registry, $xml, $ip);
		&run_query($registry,$xml);
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


#
# returns registry XML
#

### END OF MAIN PROGRAM ###

sub get_registry {
    
    my ($registry,$server_host,$server_port,$path)=@_;
    

    my $xml = $registry->toXML();
    my $reg_file = XMLin($xml, forcearray=> [qw(virtualSchema RegistryURLLocation RegistryDBLocation MartDBLocation MartURLLocation)], keyattr => [],KeepRoot=>1);
    
    my $mr =$reg_file->{'MartRegistry'};
	
    while (my ($key,$value) = each (%{$mr})){
	
	
	if ($mr->{'virtualSchema'}){	
	    foreach my $lr (@{$mr->{'virtualSchema'}}){
		&_set_location($lr);
	    }
	} else {
	    &_set_location($mr);
	}
}
    
    
    if ($mr->{'virtualSchema'}){
	foreach my $lr (@{$mr->{'virtualSchema'}}){
	    &_reset_attributes($lr);
	} 	
    } else {
	&_reset_attributes($mr);
    }
    

    my $newconfig=XMLout($reg_file, keyattr => [],KeepRoot=>1);
    
    #pprint STDERR "\n$newconfig";
    if ($newconfig) {
	print "\n$newconfig";
    }
    else{
	BioMart::Exception::Usage->throw("Problem retrieving registry");
    }

}


sub _set_location {
    
    my ($lr)=@_;
    
    my $serverVirtualSchema = 'default';
    
    if (defined  $lr->{'name'})
    {
	$serverVirtualSchema=$lr->{'name'};
    }
    
    my @new_location;
    my @to_ignore = qw (schema databaseType user password);
    foreach my $location_atts (@{$lr->{'MartDBLocation'}}){
	
	while (my ($att,$val) = each (%{$location_atts})){
	    delete $$location_atts{$att} if (grep $att eq $_, @to_ignore);
	}
	my %new_location_atts= %$location_atts;
	$new_location_atts{'serverVirtualSchema'} = $serverVirtualSchema;
	push (@new_location,\%new_location_atts);
    }
    
    if (@new_location > 0) {
	$lr->{'MartURLLocation'}=\@new_location;
    }
    delete ($lr->{'MartDBLocation'});  
} 


sub _reset_attributes {
    my ($lr)=@_;
    
    foreach my $dblc (@{ $lr->{'MartURLLocation'} })
    {
	unless ($dblc->{'redirect'} && $dblc->{'redirect'}==1){
	    
	    $dblc->{'host'}=$server_host;
	    $dblc->{'port'}=$server_port;
	    $dblc->{'path'}=$path;
	    
	}
    }
    
}


#
# returns datasets tab delimited
#

sub get_datasets {
    
    my ($registry,$vschema_name,$mart_name,$mart_user)=@_;
    my $output; 
    if (!$vschema_name || $vschema_name eq ''){
	my $seen;
	foreach my $virtualSchema (@{$registry->getAllVirtualSchemas}){
	    foreach my $location (@{$virtualSchema->getAllLocations}){
		next unless ($location->name eq $mart_name);
		if ($seen){
		    # duplicated mart name as virtual_schema_name not set
		    print "\nMart name conflict for $mart_name. Need to further qualify with the virtualSchemaName as well\n";
		    return;
		}
		$vschema_name = $virtualSchema->name;
		$seen++;
	    }
	}
    }

    my $names=$registry->getAllDatasetNames($vschema_name);
    

    foreach my $ppname (@$names){
	my $dataset = $registry->getDatasetByName($vschema_name, $ppname,$mart_user);
	next if (!$dataset);
	if ($mart_name eq $dataset->locationName) {
	    my $type;
	    if ($dataset->isa("BioMart::Dataset::TableSet")) {
		$type="TableSet";
	    }
	    else {
		$type ="GenomicSequence";
	    }
	    
	    $output .= " \n";
	    
	    $output .=  "$type\t".$dataset->name."\t".$dataset->displayName."\t".$dataset->visible."\t".$dataset->version."\t".$dataset->initialBatchSize."\t".$dataset->maxBatchSize."\t".$dataset->interfaces."\t".$dataset->modified."\n";
	    
	}
    }
    if ($output) {
	print "$output";
    }
    else{
	BioMart::Exception::Usage->throw("Problem retrieving datasets for mart $mart_name, check your parameters");
    }
}

sub get_interfaces{
    my ($registry,$vschema_name,$mart_name,$mart_user,$dataset_name)=@_;
    my $dataset=$registry->getDatasetByName($vschema_name, $dataset_name,$mart_user);
    my $output;
    if ($dataset){
	$output .= "\n".$dataset->interfaces."\n";
    }

    if ($output) {
	print "$output";
    }
    else{
	BioMart::Exception::Usage->throw("Problem retrieving interfaces for dataset $dataset_name in mart $mart_name and schema $vschema_name, check your parameters");
    }

    return;
}


#
# check if mart config version matches client version - returns boolean
#

sub version_check {
    my ($registry,$vschema_name,$mart_name,$version)=@_;
    
    my $mart=&_find_mart($registry,$vschema_name,$mart_name);
    print "\n".$mart->versionCheck($version)."\n";
    return;
    
    
}

#
# returns mart config version
#

sub version {
    my ($registry,$vschema_name,$mart_name)=@_;
    
    my $mart=&_find_mart($registry,$vschema_name,$mart_name);
    print "\n".$mart->version()."\n";
    return;
       
}



sub _find_mart {

    my ($registry,$vschema_name,$mart_name)=@_;


 my $found_location;
    my $seen;
    foreach my $virtualSchema (@{$registry->getAllVirtualSchemas}){
	next unless (!$vschema_name || $vschema_name eq '' || $virtualSchema->name eq $vschema_name);
	foreach my $location (@{$virtualSchema->getAllLocations}){
	    next unless ($location->name eq $mart_name);
	    if ($seen){
		# duplicated mart name as vschema_name not set
		print "\nMart name conflict for $mart_name. Need to further qualify with the virtualSchemaName as well\n";
		return;
	    }
	    $found_location = $location;
	    $seen++;
            #print "\n".$location->versionCheck($version)."\n";
	    #return;
	}
    }
    if (!$found_location){
	print "\nMart name $mart_name not found on server for the serverVirtualSchema specified\n";
	return;
    }

    return $found_location;

}


sub get_configuration {
    
    my ($registry,$vschema_name,$dataset_name,$interface,$mart_user)=@_;
    
    
    if (!$vschema_name || $vschema_name eq ''){
	my $seen;
	foreach my $virtualSchema (@{$registry->getAllVirtualSchemas}){
	    foreach my $dsetName (@{$registry->getAllDatasetNames($virtualSchema->name)}){
		next unless ($dsetName eq $dataset_name);
		if ($seen){
		    # duplicated mart name as vschema_name not set
		    print "\nDataset name conflict for $dataset_name. Need to further qualify with the virtualSchemaName as well\n";
		    return;
		}
		$vschema_name = $virtualSchema->name;
		$seen++;
	    }
	}
    }
    
    my $xmlTree;
    my $dset = $registry->getDatasetByName($vschema_name, $dataset_name,$mart_user);
    $xmlTree = $dset->getConfigurationTree($interface)->toXML() if ($dset);

    if ($xmlTree){
	print  "$xmlTree\n";
    }
    else{
	BioMart::Exception::Usage->throw("Problem retrieving configuration for dataset $dataset_name in mart $mart_name and schema $vschema_name, check your parameters");
    }

}

sub get_filters {
    
    my ($registry,$vschema_name,$dataset_name,$interface,$mart_user)=@_;
    
    
    if (!$vschema_name || $vschema_name eq ''){
	my $seen;
	foreach my $virtualSchema (@{$registry->getAllVirtualSchemas}){
	    foreach my $dsetName (@{$registry->getAllDatasetNames($virtualSchema->name)}){
		next unless ($dsetName eq $dataset_name);
		if ($seen){
		    # duplicated mart name as vschema_name not set
		    print "\nDataset name conflict for $dataset_name. Need to further qualify with the virtualSchemaName as well\n";
		    return;
		}
		$vschema_name = $virtualSchema->name;
		$seen++;
	    }
	}
    }
    
    my $dset = $registry->getDatasetByName($vschema_name, $dataset_name,$mart_user);
    my $ct = $dset->getConfigurationTree($interface) if ($dset);
    my $output;
    if ($ct){
	foreach my $fpage (@{$ct->getAllFilterTrees}){
	    next if ($fpage->hideDisplay eq 'true'); 
	    foreach my $fgroup (@{$fpage->getAllFilterGroups}){
		foreach my $fcollection(@{$fgroup->getAllCollections}){
		    foreach my $filter(@{$fcollection->getAllFilters}){
			if ($filter->displayType eq 'container'){
			    foreach my $option(@{$filter->getAllOptions}){
				#print $option->filter->name."\t".$option->filter->displayName."\t[]"."\n";
				my $options = $option->filter->getAllOptions;
				my @vals;
				foreach (@$options){
				    push @vals,$_->value;
				}
				$output .= $option->filter->name."\t".$option->filter->displayName."\t[".join(",",@vals)."]\t".$option->filter->description."\n";
			    }
			}
			else{
			    my $options = $filter->getAllOptions;
			    my @vals;
			    foreach (@$options){
				push @vals,$_->value;
			    }
			    $output .= $filter->name."\t".$filter->displayName."\t[".join(",",@vals)."]\t".$filter->description."\n";
			}
		    }
		}
	    }
	}
	$output .=  "\n";
    }
    if ($output) {
	print "\n$output";
    }
    else{
	BioMart::Exception::Usage->throw("Problem retrieving filters for dataset $dataset_name in schema $vschema_name, check your parameters");
    }
}

sub get_attributes {
    
    my ($registry,$vschema_name,$dataset_name,$interface,$mart_user)=@_;
        
    if (!$vschema_name || $vschema_name eq ''){
	my $seen;
	foreach my $virtualSchema (@{$registry->getAllVirtualSchemas}){
	    foreach my $dsetName (@{$registry->getAllDatasetNames($virtualSchema->name)}){
		next unless ($dsetName eq $dataset_name);
		if ($seen){
		    # duplicated mart name as vschema_name not set
		    print "\nDataset name conflict for $dataset_name. Need to further qualify with the virtualSchemaName as well\n";
		    return;
		}
		$vschema_name = $virtualSchema->name;
		$seen++;
	    }
	}
    }
    
    my $dset = $registry->getDatasetByName($vschema_name, $dataset_name,$mart_user);
    my $ct = $dset->getConfigurationTree($interface) if ($dset);
    my $output;
    #print "\n";
    if ($ct){
	foreach my $apage (@{$ct->getAllAttributeTrees}){
	    next if ($apage->hideDisplay eq 'true'); 
	    foreach my $agroup (@{$apage->getAllAttributeGroups}){
		foreach my $acollection(@{$agroup->getAllCollections}){
		    foreach my $attribute(@{$acollection->getAllAttributes}){
			$output .= $attribute->name."\t".$attribute->displayName."\t".$attribute->description."\n";
		    }
		}
	    }
	}
	$output .=  "\n";
    }
    if ($output){
	print "\n$output";
    }
    else{
	BioMart::Exception::Usage->throw("Problem retrieving attributes for dataset $dataset_name in schema $vschema_name, check your parameters");
    }
}


sub run_query {
    my ($registry,$xml) = @_;
    my $query;	
   
    $LOGGER->warn("RECEIVED QUERY:$xml\n");
      
	eval{
	    $query = BioMart::Query->new(
				 'registry' => $registry,
				 'virtualSchemaName' => 'default',
				 'xml'      => $xml);
    
    		my $query_planner = BioMart::QueryRunner->new();
    		$query_planner->execute($query);
    
    		if ($query->count eq '1'){
			my $count = $query_planner->getCount();
			print "\n$count\n"; 
    		}
    		else{	
		        if ($query->header && $query->header eq '1') {
			    $query_planner->printHeader();
			}
			$query_planner->printResults();
			$query_planner->printFooter();
	    	}
	};

    
	if($@) {
    		my $ex = Exception::Class->caught('BioMart::Exception');
	   	if(!$ex) {
			$ex = BioMart::Exception->new('non-BioMart die(): '.$@);
	    	}
	    	my $errmsg = "Query ERROR: caught ".ref($ex) . ": " . $ex->error();
	    	print $errmsg;
	}    }

sub createLog
{
	my ($registry,$xml, $ip) = @_;
	## extraction of requestid, not removing it from query as its ignored even if it
	## travels down to the query engine
	my ($mode, $log_query, $log_ip);

	my $hash = $registry->settingsParams();
     foreach(keys %$hash) {     	
	     if($_ eq "webserviceLogging") {
	     	foreach my $param (keys %{$hash->{$_}}) {
     			#print "\n\t\t\t$param \t", $hash->{$_}->{$param};
     			$mode = 1 	if($param eq 'mode' && $hash->{$_}->{$param} eq 'ON');
	    			$log_query = 1 if($param eq 'log_query' && $hash->{$_}->{$param} eq 'ON');
     			$log_ip = 1  	if($param eq 'log_IP' && $hash->{$_}->{$param} eq 'ON');     			
     		}
     	}
     }

	if($mode) ## do logging
	{
		my $reqLogFile = $log_Dir."requestLog";
		open(STDREQLOG, ">>$reqLogFile");
	
		$xml =~ m/.*?requestid.*?\"(.*?)\".*/im;
	
		my $theTime = strftime "%Y-%m-%d %H:%M:%S", localtime;
	
		print STDREQLOG "\nIP ADDRESS: $ip" 		if ($ip && $log_ip);
		print STDREQLOG "\n$theTime" 	if ($theTime);
		print STDREQLOG "\n$1"	 	if ($1);
		print STDREQLOG "\n$xml"		if ($xml && $log_query); ## only log xml query if told to do so
	
		close(STDREQLOG);
	}
}















