package bin::ConfBuilder;

use strict;

sub makehttpdConf
{
	my ($self, %OPTIONS) = @_;
	#$self->printOptions(%OPTIONS);
	$OPTIONS{conf} =~ m/(.*\/)[^\/]*/;	
	my $confdir = $1;
	my $httpdConfFile = $1."httpd.conf";

	open(STDHTTPD,">$httpdConfFile");
	print STDHTTPD qq/
	PidFile logs\/httpd.pid
	Timeout 300
	KeepAlive On
	MaxKeepAliveRequests 100
	KeepAliveTimeout 15
	MinSpareServers 2
	MaxSpareServers 2
	StartServers 2
	MaxClients 50
	MaxRequestsPerChild 0
	Listen $OPTIONS{server_port}

	DirectoryIndex index.html

	TypesConfig conf\/mime.types
	DefaultType text\/plain
	AddType image\/gif .gif
	AddType image\/png .png
	AddType image\/jpeg .jpg .jpeg
	AddType text\/css .css
	AddType text\/html .html .htm
	AddType text\/plain .asc .txt
	AddType application\/pdf .pdf
	AddType application\/x-gzip .gz .tgz
	AddType application\/vnd.ms-excel .xls
    
	ErrorLog logs\/error_log
	LogLevel warn
	LogFormat "%h %l %u %t \\"%r\\" %>s %b" combined
	CustomLog logs\/access_log combined
	/;

	if ($OPTIONS{httpd_modperl} && $OPTIONS{httpd_modperl} eq 'DSO')
	{
		print STDHTTPD qq/
		LoadModule perl_module $OPTIONS{httpd_modperl_dsopath}
		/;
		if ($OPTIONS{httpd_modperl_dsopath_modules})
		{
			foreach (@{$OPTIONS{httpd_modperl_dsopath_modules}})
			{
				print STDHTTPD qq/
				LoadModule $_ /;
				
			}
		}
	}
	
	## for mod_gzip Apache 1.3 only
	if ($OPTIONS{httpd_version} eq '1.3')
	{
		if ($OPTIONS{httpd_modperl_dsopath_modules})
		{
			foreach (@{$OPTIONS{httpd_modperl_dsopath_modules}})
			{
				print STDHTTPD qq/
				LoadModule $_ /;				
			}
		}
	}

	if ($OPTIONS{httpd_modperl} )
	{
		print STDHTTPD qq/
		<Perl>
		/;
		
		if($OPTIONS{libdirs})
		{
			foreach (@{$OPTIONS{libdirs}})
			{
				print STDHTTPD qq/
				use lib '$_'; /;
			}
		}
		foreach (@{$OPTIONS{modules_in_dist}})
		{
			print STDHTTPD qq/
			require "$_"; /;
		}
	
		print STDHTTPD qq/	
		#warn "MartView:: Initializing master Mart registry";
		eval { my \$init = BioMart::Initializer->new(registryFile => '$OPTIONS{conf}');
		\$main::BIOMART_REGISTRY = \$init->getRegistry() || die "Can't get registry from initializer";
		};
		<\/Perl>
		/;
		
	}
	

	## APACHE 1.3 compression
		if ($OPTIONS{httpd_version} eq '1.3')
		{
			print STDHTTPD qq/
			<IfModule mod_gzip.c>
                        mod_gzip_on Yes
                        mod_gzip_can_negotiate        Yes
                        mod_gzip_static_suffix        .gz
                        AddEncoding              gzip .gz
                        mod_gzip_update_static        No
                        mod_gzip_command_version      '\/mod_gzip_status'
                        mod_gzip_temp_dir \/tmp
                        mod_gzip_keep_workfiles No
                        mod_gzip_handle_methods        GET POST
                        mod_gzip_dechunk yes
                        mod_gzip_min_http 1000
                        mod_gzip_minimum_file_size  1000
                        mod_gzip_maximum_file_size  3000000
                        mod_gzip_maximum_inmem_size 60000

                        # which files are to be compressed?
                        #
                        # The order of processing during each of both phases is not important,
                        # but to trigger the compression of a request's content this request
                        # a) must match at least one include rule in each of both phases and
                        # b) must not match an exclude rule in any of both phases.
                        # These rules are not minimal, they are meant to serve as example only.
                        #
                        # phase 1: (reqheader, uri, file, handler)
                        # ========================================
                        # (see chapter about caching for problems when using 'reqheader' type
                        #  filter rules.)
                        # NO:   special broken browsers which request for gzipped content
                        #       but then aren't able to handle it correctly
                        mod_gzip_item_exclude         reqheader  "User-agent: Mozilla\/4.0[678]"
                        #
                        # JA:   HTML-Dokumente
                        mod_gzip_item_include         file       \\.html\$
                        mod_gzip_item_include         file       \\.biomart\$
                        mod_gzip_item_include           uri .

                        #
                        # NO:   include files \/ JavaScript & CSS (due to Netscape4 bugs)
                        mod_gzip_item_exclude         file       \\.js\$
                        mod_gzip_item_exclude         file       \\.css\$
                        mod_gzip_item_exclude         file       \\.gz\$
                        mod_gzip_item_exclude         file       \\.xls\$


                        #
                        # YES:  CGI scripts
                        mod_gzip_item_include         file       \\.pl\$
                        mod_gzip_item_include         handler    ^cgi-script\$
                        #
                        # phase 2: (mime, rspheader)
                        # ===========================
                        # YES:  normal HTML files, normal text files, Apache directory listings
                        #mod_gzip_item_include         mime       ^text\/html\$
                        #mod_gzip_item_include         mime       ^text\/plain\$
                        #mod_gzip_item_include         mime       ^httpd\/unix-directory\$

                        mod_gzip_item_include mime .

                        #mod_gzip_item_include mime ^application\/vnd.ms-excel

                        #
                        # NO:   images (GIF etc., will rarely ever save anything)
                        mod_gzip_item_exclude         mime       ^image\/

                        mod_gzip_send_vary Yes
                        <\/IfModule>
			/;
		}
		

	print STDHTTPD qq/	
	DocumentRoot "$OPTIONS{htdocs}"
	<Location \/>
    	Options Indexes FollowSymLinks MultiViews
    	AllowOverride None
    	Order allow,deny
    	Allow from all
	<\/Location>

	ScriptAlias \/$OPTIONS{cgiLocation}\/martview "$OPTIONS{cgibin}\/martview"
	<Location \/$OPTIONS{cgiLocation}\/martview>

	AllowOverride None
    	Options None
    	Order allow,deny
    	Allow from all
	/;

        if ($OPTIONS{httpd_version} eq '2.0' || $OPTIONS{httpd_version} eq '2.1+')
        {
                print STDHTTPD qq/
                <IfModule mod_deflate.c>
                        ## zip both input and output
                        SetOutputFilter DEFLATE
                        SetInputFilter DEFLATE
                        ## donot zip already zipped files 
                        SetEnvIfNoCase Request_URI \\.(?:exe|t?gz|zip|bz2|sit|rar)\$ no-gzip dont-vary
                <\/IfModule>
                /;
        }

	if ($OPTIONS{httpd_modperl})
	{
		print STDHTTPD qq/SetHandler perl-script
		/;
		if ($OPTIONS{httpd_version} eq '1.3')
		{
			print STDHTTPD qq/PerlHandler Apache::Registry/;
		}
		elsif($OPTIONS{httpd_version} eq '2.0' || $OPTIONS{httpd_version} eq '2.1+')
		{
			print STDHTTPD qq/PerlResponseHandler ModPerl::Registry/;
		}
	}
	
	print STDHTTPD qq/
    	Options +ExecCGI
	<\/Location>
	/;
	
	print STDHTTPD qq/
	ScriptAlias \/$OPTIONS{cgiLocation}\/martservice "$OPTIONS{cgibin}\/martservice"
	<Location \/$OPTIONS{cgiLocation}\/martservice>
    	AllowOverride None
    	Options None
    	Order allow,deny
    	Allow from all
	/;
	
	if ($OPTIONS{httpd_modperl})
	{
		print STDHTTPD qq/SetHandler perl-script
		/;
		if ($OPTIONS{httpd_version} eq '1.3')
		{
			print STDHTTPD qq/PerlHandler     Apache::Registry/;
		}
		elsif($OPTIONS{httpd_version} eq '2.0' || $OPTIONS{httpd_version} eq '2.1+')
		{
			print STDHTTPD qq/PerlResponseHandler ModPerl::Registry/;
		}
	}
	print STDHTTPD qq/
    	Options +ExecCGI
	<\/Location>
	/;
	
	print STDHTTPD qq/
	ScriptAlias \/$OPTIONS{cgiLocation}\/martresults "$OPTIONS{cgibin}\/martresults"
	<Location \/$OPTIONS{cgiLocation}\/martresults>
    	AllowOverride None
    	Options None
    	Order allow,deny
    	Allow from all
	/;
	
	if ($OPTIONS{httpd_modperl})
	{
		print STDHTTPD qq/SetHandler perl-script
		/;
		if ($OPTIONS{httpd_version} eq '1.3')
		{
			print STDHTTPD qq/PerlHandler     Apache::Registry/;
		}
		elsif($OPTIONS{httpd_version} eq '2.0' || $OPTIONS{httpd_version} eq '2.1+')
		{
			print STDHTTPD qq/PerlResponseHandler ModPerl::Registry/;
		}
	}
	print STDHTTPD qq/
    	Options +ExecCGI
	<\/Location>
	/;

	if ($OPTIONS{httpd_modperl})
	{
		print STDHTTPD qq/
		<Location \/$OPTIONS{cgiLocation}\/perl-status>/;

		print STDHTTPD qq/
			SetHandler perl-script
		/;
		if ($OPTIONS{httpd_version} eq '1.3')
		{
			print STDHTTPD qq/PerlHandler Apache::status/;
		}
		elsif($OPTIONS{httpd_version} eq '2.0' || $OPTIONS{httpd_version} eq '2.1+')
		{
			print STDHTTPD qq/PerlHandler Apache2::Status/;
		}
		
		print STDHTTPD qq/
		<\/Location>
		/;

	}

	close(STDHTTPD);	
}

sub makeMartView
{
	my ($self, %OPTIONS) = @_;
	undef $/; ## whole file mode for read
	my $file = $OPTIONS{cgibin}."/martview.PLS";	
	open(STDMARTVIEW, "$file");	
	my $fileContents = <STDMARTVIEW> ;
	close(STDMARTVIEW);
	#print $fileContents;
	##---------------- replacing [TAG:lib]
	my $libPaths;
	if ($OPTIONS{libdirs})
	{
		foreach my $path(@{$OPTIONS{libdirs}})
		{	
			$libPaths .= qq/use lib "$path";\n/;
		}
	}
	$fileContents =~ s/\[TAG:lib\]/$libPaths/m;

	##---------------- replacing [TAG:conf]
	if ($OPTIONS{conf})
	{
		my $confFile = qq/\$CONF_FILE = '$OPTIONS{conf}';\n/; 
		$fileContents =~ s/\[TAG:conf\]/$confFile/m;
	}
	
	$file = $OPTIONS{cgibin}."/martview";	
	open(STDMARTVIEW, ">$file");	
	print STDMARTVIEW $fileContents;
	close(STDMARTVIEW);

	chmod 0755, $file;		
}
sub makeMartService
{
	my ($self, %OPTIONS) = @_;
	undef $/; ## whole file mode for read
	my $file = $OPTIONS{cgibin}."/martservice.PLS";	
	open(STDMARTSERVICE, "$file");	
	my $fileContents = <STDMARTSERVICE> ;
	close(STDMARTSERVICE);
	#print $fileContents;
	##---------------- replacing [TAG:lib]
	my $libPaths;
	if ($OPTIONS{libdirs})
	{
		foreach my $path(@{$OPTIONS{libdirs}})
		{	
			$libPaths .= qq/use lib "$path";\n/;
		}
	}
	$fileContents =~ s/\[TAG:lib\]/$libPaths/m;

	##---------------- replacing [TAG:conf]
	if ($OPTIONS{conf})
	{
		my $confFile = qq/\$CONF_FILE = '$OPTIONS{conf}';\n/; 
		$fileContents =~ s/\[TAG:conf\]/$confFile/m;
	}

	##---------------- replacing [TAG:server_host]
	if ($OPTIONS{server_host})
	{
		my $server_host = qq/\$server_host = '$OPTIONS{server_host}';\n/; 
		$fileContents =~ s/\[TAG:server_host\]/$server_host/m;
	}

	##---------------- replacing [TAG:cgiLocation]
	if ($OPTIONS{cgiLocation})
	{
		my $cgiLocation = qq/\$cgiLocation = '$OPTIONS{cgiLocation}';\n/; 
		$fileContents =~ s/\[TAG:cgiLocation\]/$cgiLocation/m;			
	}

	##---------------- replacing [TAG:server_port]
	if ($OPTIONS{server_port})
	{
		my $server_port;
		if($OPTIONS{proxy}) 
		{
			$server_port = qq/\$server_port = '$OPTIONS{proxy}';\n/; 
		}
		else
		{
			$server_port = qq/\$server_port = '$OPTIONS{server_port}';\n/; 
		}
			
		$fileContents =~ s/\[TAG:server_port\]/$server_port/m;
			
	}
	
	##---------------- replacing [TAG:log_dir]
	my $logDir = qq/\$log_Dir = '$OPTIONS{logDir}';\n/;
	$fileContents =~ s/\[TAG:log_dir\]/$logDir/m;
	
	$file = $OPTIONS{cgibin}."/martservice";	
	open(STDMARTSERVICE, ">$file");	
	print STDMARTSERVICE $fileContents;
	close(STDMARTSERVICE);

	chmod 0755, $file;		
}

sub makeMartResults
{
	my ($self, %OPTIONS) = @_;
	undef $/; ## whole file mode for read
	my $file = $OPTIONS{cgibin}."/martresults.PLS";	
	open(STDMARTRES, "$file");	
	my $fileContents = <STDMARTRES> ;
	close(STDMARTRES);
	#print $fileContents;
	##---------------- replacing [TAG:lib]
	my $libPaths;
	if ($OPTIONS{libdirs})
	{
		foreach my $path(@{$OPTIONS{libdirs}})
		{	
			$libPaths .= qq/use lib "$path";\n/;
		}
	}
	$fileContents =~ s/\[TAG:lib\]/$libPaths/m;

	$file = $OPTIONS{cgibin}."/martresults";	
	open(STDMARTRES, ">$file");	
	print STDMARTRES $fileContents;
	close(STDMARTRES);

	chmod 0755, $file;		
}

sub updateMainTemplate
{
	my ($self, %OPTIONS) = @_;
	
	undef $/; ## whole file mode for read
	$OPTIONS{conf} =~ m/(.*\/)[^\/]*/;
	my $confDir = $1;
	my $file = $confDir."/templates/default/main.tt_template";
	open(STDMAINTEMPLATE, "$file");	
	my $fileContents = <STDMAINTEMPLATE> ;
	close(STDMAINTEMPLATE);
	
	##---------------- replacing [TAG:path]
	$fileContents =~ s/\[TAG:path\]/$OPTIONS{cgiLocation}/g;

	$file = $confDir."/templates/default/main.tt";
	open(STDMAINTEMPLATE, ">$file");	
	print STDMAINTEMPLATE $fileContents;
	close(STDMAINTEMPLATE);

	chmod 0755, $file;
}
sub makeCopyDirectories
{
	my ($self, %OPTIONS) = @_;
	
	my $path = $OPTIONS{htdocs}.'/'.$OPTIONS{cgiLocation}.'/mview/';
	
	system("mkdir -p $path");
		
	my $source = $OPTIONS{htdocs}.'/martview/*';
	my $destination = $path;
	system("cp -r $source $destination");
	
#	print "\nPATH:  ",$path, "\n";
#	print "\nSOURCE:  ",$source, "\n";
	
}

sub printOptions
{
	my ($self, %OPTIONS) = @_;	
	foreach my $key (keys %OPTIONS)
	{
		if($key eq 'modules_in_dist' || $key eq 'libdirs')
		{
			print "\n", $key, " \t\t>>>> ", @{$OPTIONS{$key}}, "\n";
		}
		else
		{
			print "\n", $key, " \t\t>>>> ", $OPTIONS{$key}, "\n";
		}
	}

}

1;
