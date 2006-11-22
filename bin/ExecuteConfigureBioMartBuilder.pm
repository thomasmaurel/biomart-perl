package bin::ExecuteConfigureBioMartBuilder;

use strict;
use Cwd;
use English;

sub executeSystemCommand
{
#	print "\nFINAL COMMAND: $ARG[1]\n";
	my $command = Cwd::cwd.'/bin/'.$ARG[1];
#	print "\nFINAL COMMAND: $command\n";
	system("perl $command");	
}

1;
