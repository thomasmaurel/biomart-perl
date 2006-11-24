use strict;
use warnings;
use English;
use Cwd;
use Log::Log4perl qw/:levels/;
use Sys::Hostname;
use Config;
use File::Basename qw(dirname basename);
use File::Path;
use IO::File;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use BioMart::Web::TemplateBuilder;
use bin::ConfBuilder;
use Data::Dumper;

my %OPTIONS;
my %ARGUMENTS;
$OPTIONS{logDir} = Cwd::cwd()."/logs/";
$OPTIONS{conf} = Cwd::cwd()."/conf/";
for (my $i = 0; $i < scalar(@ARGV); $i++)
{
	if ($ARGV[$i] eq "--recompile") 	{	$ARGUMENTS{recompile} = $ARGV[$i];	}
	if ($ARGV[$i] eq "--cached")		{	$ARGUMENTS{cached} = $ARGV[$i];	}
	if ($ARGV[$i] eq "--clean")		{	$ARGUMENTS{clean} = $ARGV[$i];	}
	if ($ARGV[$i] eq "--update")		{	$ARGUMENTS{update} = $ARGV[$i];	}
	if ($ARGV[$i] eq "--backup")		{	$ARGUMENTS{backup} = $ARGV[$i];	}
	if ($ARGV[$i] eq "--memory" || $ARGV[$i] eq "--m")	{	$ARGUMENTS{memory} = $ARGV[$i];	}
	if ($ARGV[$i] eq "--lazyload" || $ARGV[$i] eq "--l")	{	$ARGUMENTS{lazyload} = $ARGV[$i];	}
	if ($ARGV[$i] eq "-r" || $ARGV[$i] eq "-registryFile")	
	{	
		if($ARGV[$i+1])	{	$ARGUMENTS{"-r"} = $ARGV[$i+1];	}
	}
			
}

if ($ARGUMENTS{"-r"})
{
	#print  $ARGUMENTS{registryFile}, "\n";
	$ARGUMENTS{"-r"} =~ m/.*?\/?([^\/]*)\Z/;
	$OPTIONS{conf} .= $1;	
}
else
{
	#$OPTIONS{conf}.="defaultMartRegistry.xml";
	print "\nSwitch -r followed by registryFileName is missing, Can't proceed.\n";
	exit;
	
}

if (! -e $OPTIONS{conf}) { BioMart::Exception::Configuration->throw ("ConfigureBioMart.pl: Registry File $OPTIONS{conf} does not exist under directory conf/");  exit ;}

# Initalize logging framework if not already done, and get reference to logger
#$ARGUMENTS{verbose} and Log::Log4perl->appender_thresholds_adjust(1);
Log::Log4perl->init_once(dirname($OPTIONS{conf}).'/log4perl.conf');
my $LOGGER = Log::Log4perl->get_logger(basename($0));

# If user provides verbose-flag, adjust logger behaviour accordingly
if($ARGUMENTS{verbose}) {
    $LOGGER->level($DEBUG);
    $LOGGER->debug("Have -v verbose flag, so setting logging level to DEBUG");
}
else {
    Log::Log4perl->appender_thresholds_adjust(2);
  } 

$LOGGER->debug("Initializing template builder");
#---------------------------------------------------------- NEW CODE TO AVOID BUILD - STARTS
my $httpdconfFile = Cwd::cwd() . "/conf/httpd.conf";
my $Configure = 'n';

#---------------------------------------------------------- if we change registry, and httpd.conf exists,
#---------------------------------------------------------- update it automatically
if(-e $httpdconfFile)
{
	undef $/;		
	open(STDHTTPDCONF, "$httpdconfFile");
	my $httpd_contents = <STDHTTPDCONF>;
	close(STDHTTPDCONF);
	$/="\n"; 		# setting back to default value
	$httpd_contents =~ m/.*registryFile.*\'(.*)\'.*/;
	#print $1, "\n", $OPTIONS{conf};
	if ($1 ne $OPTIONS{conf})
	{
		$httpd_contents =~ s/$1/$OPTIONS{conf}/;
		open(STDHTTPDCONF, ">$httpdconfFile");
		print STDHTTPDCONF $httpd_contents;
		close(STDHTTPDCONF);
		my $command = 'rm '.Cwd::cwd().'/conf/templates/default/'.'*.ttc';
		print "\n$command";
		system("$command");
		#$ARGUMENTS{recompile} = "--recompile";	## forcing templates compiling as you switch between baked registries, 
										## however templates could be different			
	}
	$Configure = &promptUser("\nDO YOU WANT TO USE EXISTING SERVER CONFIGURATION [y/n]\t", 'y');
}
if($Configure eq 'n' || ! -e $httpdconfFile)
{
	
	use vars qw( $build $httpd_version $httpd_modperl $httpd_modperl_dsopath);
	my @httpd_paths;

	$OPTIONS{htdocs} = Cwd::cwd() . "/htdocs";
	$OPTIONS{cgibin} = Cwd::cwd() . "/cgi-bin";
	$OPTIONS{lib}    = Cwd::cwd() . "/lib";		

	print "Checking several common Apache locations...";
	foreach my $d(qw(
		/usr/local/apache/bin /usr/local/apache2/bin 
		/usr/local/bin /usr/local/sbin 
		/usr/bin /usr/sbin 
		/bin /sbin
	)) 
	{
		foreach my $f(qw(
			apache apache2 
			httpd httpd2
		)) 
		{
			-f $d."/".$f and push @httpd_paths, $d."/".$f;
		}
	}
	print "done.\n";
	my $pathlist = join("\n\t", @httpd_paths);
	$pathlist ||= '[No plausible httpd binaries found]';
	my $i2use = &promptUser("\nSelect either one of the detected httpd paths on the list, OR enter the path you wish to use:\n\t$pathlist\n", 1);
	$i2use =~ s/\s+//g;
	if(length($i2use) <= 2) 
	{
	    $OPTIONS{httpd} = $httpd_paths[$i2use-1];
	}
	else 
	{
	    $OPTIONS{httpd} = $i2use;
	}
  
	if(-f $OPTIONS{httpd}) 
	{
		print "Got usable Apache in $OPTIONS{httpd}, probing for version & ModPerl configuration\n";
		my $httpd_version_string = `$OPTIONS{httpd} -v`;
		#warn "\$httpd_version_string='$httpd_version_string'";
		#$httpd_version = $httpd_version_string =~ m{Apache/2.0}xms ? '2.0' ## this fails incase version is 2.2
		$httpd_version = $httpd_version_string =~ m{Apache/1.3}xms ? '1.3'
	               : $httpd_version_string =~ m{Apache/2.0}xms ? '2.0'
	               : $httpd_version_string =~ m{Apache/2.}xms ? '2.1+'
			       :    undef
		     	  ;
		my $modlist_string = `$OPTIONS{httpd} -l `;
		if($modlist_string =~ /mod_perl/xms) 
		{
	    		print "Have ModPerl statically compiled into httpd, configuring ModPerl in httpd.conf.\n";
		    $httpd_modperl = 'static';	    
		}
		elsif($modlist_string =~ /mod_so/xms) 
		{
	   		# Got DSO support, see if we have mod_perl modules around too
			my $apxs = dirname($OPTIONS{httpd}).'/apxs';
			-f $apxs or $apxs .= 2;
	    		my $httpd_libdir = `$apxs -q LIBEXECDIR`;
		    	chomp($httpd_libdir);
		    	#warn "httpd_libdir = '$httpd_libdir', version='$httpd_version'";
  	   	 	$httpd_modperl_dsopath = $httpd_version eq '1.3'  ? $httpd_libdir.'/libperl.so'
		             : $httpd_version eq '2.0'  ? $httpd_libdir.'/mod_perl.so'
		             : $httpd_version eq '2.1+'  ? $httpd_libdir.'/mod_perl.so'
		 		   : undef     
				   ;
	    		#warn "httpd_modperl_dsopath = '$httpd_modperl_dsopath'";
	    		if($httpd_modperl_dsopath && -f $httpd_modperl_dsopath) 
			{
				print "Have Apache DSO-support and ModPerl library file present, configuring ModPerl in httpd.conf.\n";
				$httpd_modperl = 'DSO';
	    		}	
	    		else {undef $httpd_modperl_dsopath;}
		}
		else 
		{
	    		print "\nGot neither ModPerl compiled in, nor DSO-support + ModPerl library file present. Cant proceed with out ModPerl\n";
		    	undef $httpd_modperl;
	    		undef $httpd_modperl_dsopath;
	    		exit; ## no ModPerl, Good bye
		}
	}
	else 
	{
		print "No valid httpd binary specified, skipping Apache version and mod_perl checks. No
		httpd.conf will be generated.\n";
	}
	
	##------------------------------------------------------ adding mod_gzip module, needed for apache1.3	
	if ($httpd_version eq '1.3')
	{
		my $modlist_string = `$OPTIONS{httpd} -l `;
		if($modlist_string =~ /mod_so/xms) 
		{
	   		# Got DSO support, see if we have mod_perl modules around too
			my $apxs = dirname($OPTIONS{httpd}).'/apxs';
			-f $apxs or $apxs .= 2;
	    		my $httpd_libdir = `$apxs -q LIBEXECDIR`;
		    	chomp($httpd_libdir);
		    	my $gzipModule = $httpd_libdir.'/mod_gzip.so';
		    	#print "\n===== $gzipModule \n";
		    	if(-e $gzipModule)
		    	{	#warn "httpd_libdir = '$httpd_libdir', version='$httpd_version'";
	  	   	 	$httpd_modperl_dsopath = $httpd_libdir ;
	  	   	 	push @{$OPTIONS{httpd_modperl_dsopath_modules}}, "gzip_module ".$httpd_libdir."/mod_gzip.so";
	  	   	 	
			}
		}
	}
	##----------------------------------------------------------------------------------------------------
		
	$OPTIONS{httpd_version} = $httpd_version;
	$OPTIONS{httpd_modperl} = $httpd_modperl;
	$OPTIONS{httpd_modperl_dsopath} = $httpd_modperl_dsopath;
	##------------------------------------------------------ adding remaining modules in the dsopath DIR, needed for apache2
	if ($httpd_modperl_dsopath && ($OPTIONS{httpd_version} eq '2.0' || $OPTIONS{httpd_version} eq '2.1+')) 
	{
		my %modules = (
			"log_config_module"=>"mod_log_config",
			"mime_module"=>"mod_mime",
			"dir_module"=>"mod_dir",
			"alias_module"=>"mod_alias",
			"deflate_module"=>"mod_deflate",
			"setenvif_module"=>"mod_setenvif",
		);

		if ($OPTIONS{httpd_version} eq '2.0')
		{	                          
			$modules{"access_module"}="mod_access";		
		}
		elsif ($OPTIONS{httpd_version} eq '2.1+')
		{	
			$modules{"authz_host_module"}="mod_authz_host";		
		}

		# work out which ones are already compiled in and remove them from
		# our loadmodules list.
		my %builtinmods = ();
		my @builtin = split(/\n/, `$OPTIONS{httpd} -l`);
		shift(@builtin); # drop the header line
		for (my $i = 0; $i < scalar(@builtin); $i++) {
			$builtin[$i] =~ m/\s*(\S+)\.c\s*/; # the list contains .c files
			$builtinmods{$1} = 1;
		}
		
		my $dirName = dirname($OPTIONS{httpd_modperl_dsopath});
	
		while ( my ($modname, $soname) = each(%modules) ) {
			push @{$OPTIONS{httpd_modperl_dsopath_modules}}, $modname." ".$dirName."/".$soname.".so"
			unless $builtinmods{$soname};
		}
		
	}


	#------------------------------------------------------


	if(!exists $OPTIONS{server_host}) 
	{
		my $default_host = Sys::Hostname::hostname();
		my $server2use = &promptUser("\nEnter the server host OR default ", $default_host);
		$server2use =~ s/\s+//g;
		$OPTIONS{server_host} = $server2use;
    	}
    	if(!exists $OPTIONS{server_port}) 
	{
		my $port2use = &promptUser("\nEnter the server port OR default ", '5555');
		$port2use =~ s/\s+//g;
		$OPTIONS{server_port} = $port2use;
    	}
   	if(!exists $OPTIONS{proxy}) 
	{
		my $proxy = &promptUser("\nEnter proxy OR default ", '');
		if ($proxy)
		{
			$proxy =~ s/\s+//g;
			$OPTIONS{proxy} = $proxy;
		}
    	}
	if(!exists $OPTIONS{cgiLocation}) 
	{
		my $default_loc = "biomart";
		my $loc2use = &promptUser("\nEnter the required script location OR default ", $default_loc);
		$loc2use =~ s/\s+//g;
		$OPTIONS{cgiLocation} = $loc2use;
    	}


    	# Check if user wants to use non-standard library locations

    	my @INC_org = @INC;
    	if(exists($ENV{PERL5LIB})) 
	{
		print "Have auxiliary Perl libdirs in \$PERL5LIB, adding to \@INC\n";
		foreach my $libdir(split(':', $ENV{PERL5LIB})) 
		{
	    		@INC_org = grep({ !/\A$libdir\/{1}\Z/xms } @INC_org);
			next if $libdir =~ /\A_build/xms;
	    		#print "  $libdir\n";
	    		push @{$OPTIONS{libdirs}}, $libdir;
		}
    	}
    	if(grep({ /\A$OPTIONS{lib}\/{0,1}\Z/xms } @INC) == 0  ) 
	{
		print qq/Libdir $OPTIONS{lib} is not in \@INC, adding to \@INC\n/;
		push @{$OPTIONS{libdirs}}, $OPTIONS{lib};
    	}

	### would update OPTIONS{modules_in_dist}
	&libModules($OPTIONS{lib}); 

	bin::ConfBuilder->makehttpdConf(%OPTIONS);
	bin::ConfBuilder->makeMartView(%OPTIONS);
	bin::ConfBuilder->makeMartService(%OPTIONS);
	bin::ConfBuilder->makeMartResults(%OPTIONS);
}	

#---------------------------------------------------------- NEW CODE TO AVOID BUILD - ENDS
my $mart_registry;
my $action;
my $mode;
my $compiletemplates;

if ($ARGUMENTS{clean}) {	$action = 'clean'; }
elsif($ARGUMENTS{update}) {	$action = 'update'; }
elsif($ARGUMENTS{backup}) {	$action = 'backup'; }
else { $action = 'cached'; } ### default

if ($ARGUMENTS{lazyload}) { $mode = 'lazyload'; }
else { $mode = 'memory'; } ### default

if ($ARGUMENTS{recompile}) { $compiletemplates = 'force'; }
else { $compiletemplates = 'updated'; } ### default

#print $action, "  ", $mode;
my $init;
eval { 
	$init = BioMart::Initializer->new(registryFile=> $OPTIONS{conf}, action => $action, mode => $mode );
	$mart_registry = $init->getRegistry() || die "Can't get registry from initializer";
	};
if ($@){	
	print STDERR "\nERROR something wrong with your registry: $@\n"; exit(); 
}
	
## Load CSS SETTINGS from Script
&loadCSSSettings();

if(&whoBakedMe($init->configurationUpdated()) == 1 || $compiletemplates eq 'force')
{
	print  "Building templates for visible datasets\n";
	my $tbuilder = BioMart::Web::TemplateBuilder->new(conf => $OPTIONS{conf}, registry => $mart_registry );
	$tbuilder->build_templates() || print "Uh-oh, got some non-fatal warnings:\n\n ",$tbuilder->get_errstr();
}

##
#----------------------------------------------------------------------------------------

#==== THis function attempts to ascertain if the templates exists for a registry object returned by Initializer or not
#==== if initializer suggests to rebuild the tmeplates -Fine. If it doesnt there is still a chance that templates are not
#==== present, thats when the registry object is baked by API user. HOwever if an API user bakes an object, we build the templates
#==== using this code here and then user goes back to update ther registry object again - we cant do much about it except to explicitly
#==== issue a --recompile command
sub whoBakedMe
{
	my $initializerReturnVal = shift;
	if($initializerReturnVal eq 'true')
	{
		return 1; # recompile order By Initializer 
	}
	else ## initializerReturnVal eq 'false', if templates of datasets exist or not
	{
		my $templateDir = Cwd::cwd() . "/conf/templates/cached/";
		foreach my $schema (@{$mart_registry->getAllVirtualSchemas()}) {
			foreach my $mart (@{$schema->getAllMarts(1)}) {
		    		foreach my $dataset (@{$mart->getAllDatasets(1)}) {
		    			foreach ('attributepanel_','filterpanel_')
		    			{
		    				my $templateFile = $templateDir.$_.$schema->name.'.'.$dataset->name.'.tt';
		    				#print "\n", $templateFile;
		    				if (! -e $templateFile) { return 1; } ## rebuild templates - all of them
		    			}
		    		}
		    	}
		}
		return 0;		
	}
}

sub promptUser {

   my ($promptString,$defaultValue) = @_;
   if ($defaultValue) {
      print $promptString, "[", $defaultValue, "]: ";
   } else {
      print $promptString, ": ";
   }

   $| = 1;               # force a flush after our print
   $_ = <STDIN>;         # get the input from STDIN (presumably the keyboard)
   chomp;

   if ("$defaultValue") {
      return $_ ? $_ : $defaultValue;    # return $_ if it has a value
   } else {
      return $_;
   }
}

sub libModules
{
	my $dirname = shift;
	opendir (DIR, $dirname);
 	my @entries = readdir (DIR);
  	closedir (DIR);
   
   	foreach my $entry (@entries)
   	{
	  	next if $entry eq ".";
		next if $entry eq "..";
    		&libModules("$dirname/$entry") if -d ("$dirname/$entry");
		my $temp_name = "$dirname/$entry";
		#$temp_name =~ s/OPTIONS{lib}//;
      	#print "$temp_name\n" if ((-f ("$dirname/$entry")) && ("$dirname/$entry" =~ /\.pm/));
		if ((-f ("$dirname/$entry")) && ("$dirname/$entry" =~ /\.pm\Z/))
		{
			$temp_name =~ m/.*?biomart-perl\/(?:lib|conf)\/(.*)/;		
			push @{$OPTIONS{modules_in_dist}}, $1;
		}
   	}
}  

sub loadCSSSettings
{
	my $registryFile = $OPTIONS{conf};
	my $cssFile_template = Cwd::cwd()."/htdocs/martview/martview_template.css"; 
	my $cssFile = Cwd::cwd()."/htdocs/martview/martview.css"; 
	#print $cssFile;
	$registryFile =~ m/(.*\/)[^\/]*/;
    	#BioMart::Web::SiteDefs::configure($1); # Load settings. $1 is absolute path to registry file Directory
	undef $/; ## whole file mode for read
     open(STDCSS, $cssFile_template);
	my $fileContents = <STDCSS> ;
	close(STDCSS);

     my $hash = $mart_registry->settingsParams();
     foreach(keys %$hash) {     	
	     if($_ eq "cssSettings") {
	     	foreach my $param (keys %{$hash->{$_}}) {
     			#print "\n\t\t\t$param \t", $hash->{$_}->{$param};
     			$fileContents =~ s/\[$param\]/$hash->{$_}->{$param}/mg;
     		}
     	}
     }
     
	open(STDCSS, ">$cssFile");
	print STDCSS $fileContents;
	close(STDCSS);


          
}
